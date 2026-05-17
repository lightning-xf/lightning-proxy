package libxray

import (
	"fmt"
	"net"
	"os"
	"runtime"
	"runtime/debug"
	"strconv"
	"strings"
	"syscall"

	"github.com/xtls/xray-core/common/platform"
	"github.com/xtls/xray-core/core"
	"github.com/xtls/xray-core/features/stats"
	confserial "github.com/xtls/xray-core/infra/conf/serial"
	_ "github.com/xtls/xray-core/main/distro/all"
)

// FreeMemory releases memory back to the OS
func FreeMemory() {
	debug.FreeOSMemory()
	runtime.GC()
}

func setEnv(key, value string) {
	if value != "" {
		os.Setenv(key, value)
	}
}

var (
	xrayServer  *core.Instance
	protectPath string
)

func protectSocket(fd int) {
	if protectPath == "" {
		return
	}
	conn, err := net.Dial("unix", "@"+protectPath)
	if err != nil {
		return
	}
	defer conn.Close()

	unixConn := conn.(*net.UnixConn)
	socketFile, err := unixConn.File()
	if err != nil {
		return
	}
	defer socketFile.Close()

	rights := syscall.UnixRights(fd)
	err = syscall.Sendmsg(int(socketFile.Fd()), nil, rights, nil, 0)
	if err != nil {
		return
	}
	// Wait for ack
	buf := make([]byte, 1)
	conn.Read(buf)
}

func init() {
	// Note: platform.RegisterControlFunc was removed in newer xray-core versions
	// Socket protection is handled via localSocketPath environment variable instead
	fmt.Println("[Go] Socket 保护通过环境变量 XRAY_SOCK_PROTECT_PATH 配置")
}

func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}

// StartXray starts Xray with the given config.
func StartXray(configJSON string) string {
	if xrayServer != nil {
		return "Xray is already running"
	}

	fmt.Println("[Go] ========== Xray 启动流程开始 ==========")
	fmt.Printf("[Go] 接收到的配置长度: %d 字符\n", len(configJSON))

	const tunFdPrefix = "__XRAY_TUN_FD__="
	const assetDirPrefix = "__XRAY_ASSET_DIR__="

	// Try to get values from environment variables first (set by Kotlin)
	protectPath = os.Getenv("XRAY_SOCK_PROTECT_PATH")
	fmt.Printf("[Go] XRAY_SOCK_PROTECT_PATH (from env): %s\n", protectPath)

	// Pre-process configJSON to extract prefixes and JSON
	lines := strings.Split(configJSON, "\n")
	var actualJSON string

	fmt.Printf("[Go] 解析 %d 行配置前缀\n", len(lines))

	for _, line := range lines {
		line = strings.TrimSpace(line)
		if strings.HasPrefix(line, tunFdPrefix) {
			fdValue := line[len(tunFdPrefix):]
			fdInt, err := strconv.Atoi(fdValue)
			if err == nil && fdInt > 0 {
				os.Setenv(platform.TunFdKey, strconv.Itoa(fdInt))
				fmt.Printf("[Go] 解析到 TUN FD: %d\n", fdInt)
			}
		} else if strings.HasPrefix(line, assetDirPrefix) {
			assetDir := line[len(assetDirPrefix):]
			if assetDir != "" {
				os.Setenv("xray.location.asset", assetDir)
				os.Setenv("XRAY_LOCATION_ASSET", assetDir)
				fmt.Printf("[Go] 解析到资产目录 (payload): %s\n", assetDir)
			}
		} else if strings.HasPrefix(line, "{") {
			// Found the start of JSON, stop looking for prefixes
			idx := strings.Index(configJSON, "{")
			if idx >= 0 {
				actualJSON = configJSON[idx:]
			}
			fmt.Printf("[Go] JSON 配置起始位置: %d\n", idx)
			break
		}
	}

	// Final fallback: Ensure asset path is set. If still empty, use default Android path.
	fmt.Println("[Go] ========== 检查环境变量 ==========")
	currentAsset := os.Getenv("xray.location.asset")
	fmt.Printf("[Go] xray.location.asset (当前): %s\n", currentAsset)

	if currentAsset == "" {
		assetDir := os.Getenv("XRAY_LOCATION_ASSET")
		fmt.Printf("[Go] XRAY_LOCATION_ASSET (当前): %s\n", assetDir)
		if assetDir == "" {
			// Hardcoded fallback for app_flutter/data
			assetDir = "/data/user/0/com.lightning.proxy/app_flutter/data"
			fmt.Printf("[Go] 使用硬编码 fallback: %s\n", assetDir)
		}
		os.Setenv("xray.location.asset", assetDir)
		os.Setenv("XRAY_LOCATION_ASSET", assetDir)
	}

	// Final check
	finalAssetPath := os.Getenv("xray.location.asset")
	fmt.Printf("[Go] 最终资产路径: %s\n", finalAssetPath)

	// Ensure we only pass pure JSON to LoadJSONConfig
	actualJSON = strings.TrimSpace(actualJSON)
	fmt.Printf("[Go] JSON 配置长度: %d 字符\n", len(actualJSON))

	// Debug log
	fmt.Printf("[Go] libxray: Using asset path: %s\n", finalAssetPath)

	fmt.Println("[Go] ========== 加载 Xray 配置 ==========")
	config, err := confserial.LoadJSONConfig(strings.NewReader(actualJSON))
	if err != nil {
		snippetLen := min(len(actualJSON), 100)
		fmt.Printf("[Go] ❌ 配置加载失败: %v\n", err)
		return fmt.Sprintf("failed to load config (len=%d): %v. config snippet: %s", len(actualJSON), err, actualJSON[:snippetLen])
	}
	fmt.Println("[Go] ✅ Xray 配置加载成功")

	fmt.Println("[Go] ========== 创建 Xray 实例 ==========")
	server, err := core.New(config)
	if err != nil {
		fmt.Printf("[Go] ❌ 创建 Xray 实例失败: %v\n", err)
		return fmt.Sprintf("failed to create xray instance: %v", err)
	}
	fmt.Println("[Go] ✅ Xray 实例创建成功")

	fmt.Println("[Go] ========== 启动 Xray ==========")
	if err := server.Start(); err != nil {
		fmt.Printf("[Go] ❌ Xray 启动失败: %v\n", err)
		return fmt.Sprintf("failed to start xray: %v", err)
	}

	xrayServer = server
	fmt.Println("[Go] ✅ Xray 启动完成!")
	return ""
}

// StopXray stops the running Xray instance.
func StopXray() string {
	fmt.Println("[Go] ========== Xray 停止流程开始 ==========")
	if xrayServer == nil {
		fmt.Println("[Go] Xray 未运行, 无需停止")
		return ""
	}

	fmt.Println("[Go] 正在关闭 Xray...")
	if err := xrayServer.Close(); err != nil {
		fmt.Printf("[Go] ❌ Xray 关闭失败: %v\n", err)
		return fmt.Sprintf("failed to stop xray: %v", err)
	}

	xrayServer = nil
	debug.FreeOSMemory()
	fmt.Println("[Go] ✅ Xray 停止完成")
	return ""
}

// QueryStats returns the traffic stats.
// Format: "up,down" in bytes.
func QueryStats() string {
	if xrayServer == nil {
		return "0,0"
	}

	sm := xrayServer.GetFeature(stats.ManagerType())
	if sm == nil {
		return "0,0"
	}
	statsManager := sm.(stats.Manager)

	// Outbound stats for "proxy"
	upOut := statsManager.GetCounter("outbound>>>proxy>>>traffic>>>uplink")
	downOut := statsManager.GetCounter("outbound>>>proxy>>>traffic>>>downlink")

	// Outbound stats for "direct"
	upDir := statsManager.GetCounter("outbound>>>direct>>>traffic>>>uplink")
	downDir := statsManager.GetCounter("outbound>>>direct>>>traffic>>>downlink")

	var upVal, downVal int64
	if upOut != nil {
		upVal += upOut.Value()
	}
	if upDir != nil {
		upVal += upDir.Value()
	}
	if downOut != nil {
		downVal += downOut.Value()
	}
	if downDir != nil {
		downVal += downDir.Value()
	}

	return fmt.Sprintf("%d,%d", upVal, downVal)
}

// GetVersion returns the Xray version.
func GetVersion() string {
	return core.Version()
}
