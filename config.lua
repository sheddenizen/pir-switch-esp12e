wifiCfg =
{
    -- Connectivity
    ssid = "INNOXA-Lab2.4G",
    -- ssid = "INNOXA-Southernhay-2.4G-Shed",
    pwd = "Edinburgh2003",
}

mqttCfg =
{
    client = "powerswitch",
    switchTopic = "garden/controller/powerswitch/frontgarden/pond/switch",
    lightTopic = "garden/controller/powerswitch/frontgarden/pond/light",
    statusTopic = "garden/controller/powerswitch/frontgarden/pond/status",
    broker = "192.168.0.129",
    port = 1883,
    user = "",
    pass = "",
}

e131Cfg =
{
    universe = 1,
    channel = 143
}
