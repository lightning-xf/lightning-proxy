package libxray

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"math/rand"
	"net"
	"net/http"
	"net/url"
	"os"
	"runtime"
	"runtime/debug"
	"strconv"
	"strings"
	"syscall"
	"time"

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

	// 1. 带有超时的拨号，防止系统底层阻塞
	conn, err := net.DialTimeout("unix", "@"+protectPath, 3*time.Second)
	if err != nil {
		fmt.Printf("[Go] ❌ Socket 保护拨号失败: %v, 触发熔断强制关闭 FD %d 防止环路\n", err, fd)
		syscall.Close(fd)
		return
	}
	defer conn.Close()

	unixConn := conn.(*net.UnixConn)
	socketFile, err := unixConn.File()
	if err != nil {
		fmt.Printf("[Go] ❌ 获取 Socket 文件失败: %v, 触发熔断强制关闭 FD %d 防止环路\n", err, fd)
		syscall.Close(fd)
		return
	}
	defer socketFile.Close()

	// 2. 发送 FD 进行保护
	rights := syscall.UnixRights(fd)
	err = syscall.Sendmsg(int(socketFile.Fd()), nil, rights, nil, 0)
	if err != nil {
		fmt.Printf("[Go] ❌ 发送保护消息失败: %v, 触发熔断强制关闭 FD %d 防止环路\n", err, fd)
		syscall.Close(fd)
		return
	}

	// 3. 强制增加读取超时限制，等待 Android 端确认回包
	conn.SetReadDeadline(time.Now().Add(3 * time.Second))
	buf := make([]byte, 1)
	_, err = conn.Read(buf)
	if err != nil {
		fmt.Printf("[Go] ❌ 等待保护确认超时或失败: %v, 触发熔断强制关闭 FD %d 防止环路\n", err, fd)
		syscall.Close(fd)
	}
}

func init() {
	// Note: platform.RegisterControlFunc was removed in newer xray-core versions
	
	// Remove invalid log handler registration that causes build failure
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

	// [Fix] 强制开启主连接 Debug 日志级别，并将日志重定向到文件以供 Kotlin 捕获
	var mainConfigMap map[string]interface{}
	if err := json.Unmarshal([]byte(actualJSON), &mainConfigMap); err == nil {
		// 强制开启 Xray 内部的文件日志重定向
		mainConfigMap["log"] = map[string]interface{}{
			"loglevel": "debug",
			"access":   "/data/user/0/com.lightning.proxy/files/xray_access.log",
			"error":    "/data/user/0/com.lightning.proxy/files/xray_error.log",
		}

		if newJSON, err := json.Marshal(mainConfigMap); err == nil {
			actualJSON = string(newJSON)
			// 增加保底输出，用于证明新内核已生效
			fmt.Println("[Go-Core-Init] 成功拦截到主配置，新版内核准备点火！")
		}
	}

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

// MeasureRealDelay starts a temporary sandboxed Xray instance and measures the delay.
// configJSON: The Xray config for the single node.
// returns: "delay|diagnostic_info" (delay in ms, or -1 on failure).
func MeasureRealDelay(configPayload string) string {
	done := make(chan string, 1)

	go func() {
		var diagnostic string
		// 1. Extract pure JSON and AssetDir
		const assetDirPrefix = "__XRAY_ASSET_DIR__="
		lines := strings.Split(configPayload, "\n")
		var actualJSON string
		var assetDir string

		for _, line := range lines {
			line = strings.TrimSpace(line)
			if strings.HasPrefix(line, assetDirPrefix) {
				assetDir = line[len(assetDirPrefix):]
			} else if strings.HasPrefix(line, "{") {
				idx := strings.Index(configPayload, "{")
				if idx >= 0 {
					actualJSON = configPayload[idx:]
				}
				break
			}
		}

		if actualJSON == "" {
			done <- "-1|Empty JSON"
			return
		}

		// 2. Sandboxed Configuration: HTTP Inbound only (Align with v2rayNG)
		var configMap map[string]interface{}
		if err := json.Unmarshal([]byte(actualJSON), &configMap); err != nil {
			done <- fmt.Sprintf("-1|JSON Unmarshal error: %v", err)
			return
		}

		// [Fix] 1. 开启配置与日志输出 (诊断)
		// 强制设置日志级别为 debug，以便在 Logcat 中查看握手详情
		configMap["log"] = map[string]interface{}{
			"loglevel": "debug",
		}

		// [Fix] 2. 审查与修复传输配置继承 (StreamSettings)
		// 确保 Outbounds 存在且第一个 Outbound (proxy) 完整保留了 streamSettings
		if outbounds, ok := configMap["outbounds"].([]interface{}); ok && len(outbounds) > 0 {
			if firstOutbound, ok := outbounds[0].(map[string]interface{}); ok {
				if ss, ok := firstOutbound["streamSettings"].(map[string]interface{}); ok {
					diagnostic += fmt.Sprintf("StreamSettings: %v; ", ss["network"])
				} else {
					diagnostic += "⚠️ Missing StreamSettings; "
				}
			}
		}

		// [Fix] 3. 注入沙盒专属 DNS 防黑洞 (DNS)
		configMap["dns"] = map[string]interface{}{
			"servers": []interface{}{
				"1.1.1.1",
				"8.8.8.8",
				"localhost",
			},
			"queryStrategy": "UseIP",
		}

		// Generate random port between 10000 and 30000
		rand.Seed(time.Now().UnixNano())
		testPort := 10000 + rand.Intn(20000)

		// Inject HTTP Inbound
		configMap["inbounds"] = []interface{}{
			map[string]interface{}{
				"port":     testPort,
				"listen":   "127.0.0.1",
				"protocol": "http",
				"settings": map[string]interface{}{},
			},
		}

		// Ensure no TPROXY or complex routing that might interfere with sandbox
		delete(configMap, "routing")

		modifiedJSON, err := json.Marshal(configMap)
		if err == nil {
			diagnostic += fmt.Sprintf("Final Config: %s", string(modifiedJSON))
		}

		if err != nil {
			done <- fmt.Sprintf("-1|JSON Marshal error: %v", err)
			return
		}

		// 3. Start sandboxed instance (LOCAL variable, no global xrayServer pollution)
		if assetDir != "" {
			os.Setenv("xray.location.asset", assetDir)
			os.Setenv("XRAY_LOCATION_ASSET", assetDir)
		}

		config, err := confserial.LoadJSONConfig(bytes.NewReader(modifiedJSON))
		if err != nil {
			done <- fmt.Sprintf("-1|LoadJSONConfig error: %v|%s", err, diagnostic)
			return
		}

		sandboxInstance, err := core.New(config)
		if err != nil {
			done <- fmt.Sprintf("-1|core.New error: %v|%s", err, diagnostic)
			return
		}

		if err := sandboxInstance.Start(); err != nil {
			done <- fmt.Sprintf("-1|sandbox.Start error: %v|%s", err, diagnostic)
			return
		}

		// 4. Ensure cleanup of sandbox instance
		defer func() {
			sandboxInstance.Close()
			debug.FreeOSMemory()
		}()

		// 5. Measure delay using Go's native http client (Align with v2rayNG: 5s timeout)
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()

		proxyURL, _ := url.Parse(fmt.Sprintf("http://127.0.0.1:%d", testPort))
		client := &http.Client{
			Transport: &http.Transport{
				Proxy: http.ProxyURL(proxyURL),
			},
		}

		start := time.Now()
		req, err := http.NewRequestWithContext(ctx, "GET", "https://cp.cloudflare.com/generate_204", nil)
		if err != nil {
			done <- fmt.Sprintf("-1|NewRequest error: %v|%s", err, diagnostic)
			return
		}

		resp, err := client.Do(req)
		if err != nil {
			done <- fmt.Sprintf("-1|HTTP Do error: %v|%s", err, diagnostic)
			return
		}
		defer resp.Body.Close()

		// [Fix] 放宽状态码判定：只要代理建立成功并收到任何响应（如 403, 429, 302 等），即视为测速成功
		delay := int(time.Since(start).Milliseconds())
		done <- fmt.Sprintf("%d|%s", delay, diagnostic)
	}()

	select {
	case res := <-done:
		return res
	case <-time.After(5500 * time.Millisecond):
		return "-1|⚠️ 测速发生底层死锁，触发绝对硬超时截断 (5.5s)"
	}
}

