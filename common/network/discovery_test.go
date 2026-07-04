package network

import (
	"testing"
	"time"

	"fyaudio/common/protocol"
)

func TestGetBroadcastAddrs(t *testing.T) {
	addrs := GetBroadcastAddrs()
	if len(addrs) == 0 {
		t.Log("No broadcast addresses found, fallback to 255.255.255.255")
	}
	
	for _, addr := range addrs {
		t.Logf("Broadcast address: %s", addr)
	}
}

func TestGetBroadcastAddr(t *testing.T) {
	addr := GetBroadcastAddr()
	if addr == "" {
		t.Error("GetBroadcastAddr should return non-empty string")
	}
	t.Logf("Primary broadcast address: %s", addr)
}

func TestGetLocalIPs(t *testing.T) {
	ips := GetLocalIPs()
	if len(ips) == 0 {
		t.Log("No local IPs found")
	}
	
	for _, ip := range ips {
		t.Logf("Local IP: %s", ip)
	}
}

func TestDiscoveryServiceIntegration(t *testing.T) {
	svc1, err := NewDiscoveryService("FY-TEST-SVC1", "TestDevice1", "windows", protocol.RoleSource)
	if err != nil {
		t.Fatalf("Failed to create DiscoveryService 1: %v", err)
	}

	deviceOnline := make(chan *protocol.DeviceInfo, 1)
	svc1.OnDeviceOnline(func(info *protocol.DeviceInfo) {
		t.Logf("Service 1 detected device: %s (%s)", info.DeviceName, info.DeviceID)
		deviceOnline <- info
	})

	if err := svc1.Start(); err != nil {
		t.Fatalf("Failed to start DiscoveryService 1: %v", err)
	}

	time.Sleep(1 * time.Second)

	svc1.Close()

	t.Log("DiscoveryService integration test completed")
}

func TestDiscoveryServiceHeartbeat(t *testing.T) {
	svc1, err := NewDiscoveryService("FY-TEST-HB1", "HeartbeatTest1", "windows", protocol.RoleSource)
	if err != nil {
		t.Fatalf("Failed to create DiscoveryService: %v", err)
	}
	defer svc1.Close()

	if err := svc1.Start(); err != nil {
		t.Fatalf("Failed to start DiscoveryService: %v", err)
	}

	time.Sleep(2 * time.Second)

	devices := svc1.GetDevices()
	t.Logf("Devices after 2s: %d", len(devices))

	time.Sleep(protocol.HeartbeatInterval + 1*time.Second)

	devices = svc1.GetDevices()
	t.Logf("Devices after heartbeat: %d", len(devices))
}

func TestDiscoveryServiceSendSetSource(t *testing.T) {
	svc, err := NewDiscoveryService("FY-TEST-SS1", "SourceTest", "windows", protocol.RoleReceiver)
	if err != nil {
		t.Fatalf("Failed to create DiscoveryService: %v", err)
	}
	defer svc.Close()

	if err := svc.Start(); err != nil {
		t.Fatalf("Failed to start DiscoveryService: %v", err)
	}

	time.Sleep(1 * time.Second)

	err = svc.SendSetSource("FY-TARGET-SRC", "TargetSource")
	if err != nil {
		t.Errorf("SendSetSource failed: %v", err)
	}
}

func TestDiscoveryServiceSendVolumeSync(t *testing.T) {
	svc, err := NewDiscoveryService("FY-TEST-VS1", "VolumeTest", "windows", protocol.RoleReceiver)
	if err != nil {
		t.Fatalf("Failed to create DiscoveryService: %v", err)
	}
	defer svc.Close()

	if err := svc.Start(); err != nil {
		t.Fatalf("Failed to start DiscoveryService: %v", err)
	}

	time.Sleep(1 * time.Second)

	err = svc.SendVolumeSync(75)
	if err != nil {
		t.Errorf("SendVolumeSync failed: %v", err)
	}
}