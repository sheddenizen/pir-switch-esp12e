require("config")

battMvNumer = 29997
battMvDenom =1024
sleep_secs = 10
monitor_cycle_period_ms = 60000
undervoltageMv = 22500

status = {
    supplyMv = 0,
    undervoltage = 0,
    switch = {},
    light = {}
}

shutdownCount = 5

function verbose(str)
end

function info(str)
    print("i: "..str)
end

function warn(str)
    print("w: "..str)
end

function fail(str)
    print("f: "..str)
end

function read_batt_mv()
    local adcval = 0
    for n = 1, 10 do
        adcval = adcval+ adc.read(0)
    end
    status.supplyMv = adcval * battMvNumer / battMvDenom / 10
    info("Supply: "..status.supplyMv)
end

function xmit_cleanup()
    wifi.sta.disconnect()
    wifi.setmode(wifi.NULLMODE)
    -- Sleep 60s for now
    info("Supply: "..status.supplyMv)
    info("Sleepy time")
    info("Sleepy time")
    -- no, just restart
    node.restart()
    -- rtctime.dsleep(sleep_secs * 1000000, 4)
end

function mqtt_finish(client)
    mqClnt:close()
    tmr.stop(1)
    tmr.unregister(1)
    tmr.register(1, 500, tmr.ALARM_SINGLE, xmit_cleanup)
    tmr.start(1)
end


function send_status()
    info("sending status")
    -- Send battery level, QoS 1, retain
    mqClnt:publish(mqttCfg.statusTopic, sjson.encode(status), 1, 1)
end

function monitor()
    read_batt_mv()
    -- Shut down if undervoltage, unless we are just running on USB
    if (status.supplyMv < undervoltageMv and status.supplyMv > 5000)
    then
        -- Despite taking multiple samples, we sometimes get spurious readings so use a countdown to be sure
        shutdownCount = shutdownCount - 1
        status.undervoltage = 1
        warn("Undervoltage! Supply: "..status.supplyMv.." Remaining: "..shutdownCount)
    else
        status.undervoltage = 0
        shutdownCount = 5
    end
    
    if (shutdownCount < 1)
        then
        warn("Shutdown due to Undervoltage!")
        for n = 1, 3 do
            gpio.write(n, gpio.LOW)
            status.switch[n] = 0
            pwm.setduty(n+4,0)
        end
        mqClnt:publish(mqttCfg.statusTopic, sjson.encode(status), 1, 1, mqtt_finish)
    else
        send_status()
        tmr.register(0, monitor_cycle_period_ms, tmr.ALARM_SINGLE, monitor)
        tmr.start(0)
    end
end

function mqtt_message_cb(client,topic,message)
    info("Rx'd: "..topic..", '"..message.."'")
    -- All digits at end of string
    info ("channel ")
    
    local out = tonumber(string.gsub(topic, "^.*/(%d+)$", "%1"), 10)
    local val = tonumber(message, 10)
    
    if (out == nil or val == nil or out > 3 or out < 0 or val < 0)
    then
        warn("Invalid input, channel: "..string.gsub(topic, "^.*/(%d+)$", "%1")
        ..", message: "..message..", ignoring")
    else
        if (string.find(topic, mqttCfg.lightTopic) == nil)
        then
            if (val > 0) then val = 1 end
            gpio.write(out+1, val)
            status.switch[out+1] = val
            info("Switched channel "..out.." to "..val)
        else
            if (val > 255) then val = 255 end
            pwm.setduty(out+5, val * 4)
            status.light[out+1] = val
            info("Set light channel "..out.." to "..val)
        end
    end    
    send_status()    
end

function mqtt_connect_cb(client)
    info("mqtt connected, send subscribe")
    mqClnt:subscribe({[mqttCfg.switchTopic.."/+"]=1, [mqttCfg.lightTopic.."/+"]=1})
    monitor()
end

function wifi_connected_cb(tbl)
    info("wifi connected"..sjson.encode(tbl))
    mqClnt:connect(mqttCfg.broker, mqttCfg.port, 0, 0, mqtt_connect_cb, mqtt_fail_cb)

    -- Set up e1.31 multicast receive
    s = net.createUDPSocket()
    e131Ip = "239.255."..(e131Cfg.universe/256).."."..(e131Cfg.universe % 256)
    s:listen(5568, e131Ip)
    s:on("receive", e131_rx)
    net.multicastJoin("", e131Ip)

end

function wifi_fail_cb(tbl)
    fail("wifi failed: "..sjson.encode(tbl))
    xmit_cleanup()
end

function mqtt_fail_cb(client, reason)
    fail("mqtt failed, reason: "..reason)
    xmit_cleanup()
end

function mqtt_offline_cb(client)
    info("mqtt offline")
    xmit_cleanup()
end

function e131_rx(skt,data,port,ip)
     verbose("Rx: "..ip..":"..port.." "..string.len(data))
     -- Big enough to be a data packet including our channels
     if (string.len(data) < (125 + 3 + e131Cfg.channel)) then 
        verbose("Rejected, too small")
        return 
     end

    local typeId = "ASC-E1.17\000\000\000" 
    if (string.sub(data, 5, 16) ~= typeId) then
        verbose("Rejected, not e1.17 "..string.byte(data, 5)..string.byte(data, 6)..string.sub(data, 5, 16))
        return
    end    
    if (string.byte(data, 22) ~= 4) then
        verbose("Rejected, not e1.31 PDU "..string.byte(data, 22))
        return
    end    
    if (string.byte(data, 44) ~= 2) then
        verbose("Rejected, not DMP "..string.byte(data, 44))
        return
    end
    for n = 0, 2 do
        local val = string.byte(data, 126 + e131Cfg.channel + n)
        pwm.setduty(n+5, val * 4)
        status.light[n+1] = val
        verbose("Set light channel "..n.." to "..val)
    end
end    


function switch_start()

    -- Init outputs
    for n = 1, 3 do
        gpio.mode(n, gpio.OUTPUT)
        gpio.write(n, gpio.LOW)
        status.switch[n] = 0
    end

    for n = 5, 7 do
        pwm.setup(n, 1000, 0)
        pwm.start(n)
        status.light[n-4] = 0
    end

    -- Init and set ADC input.
    adc.force_init_mode(adc.INIT_ADC)

    -- Get battery voltage
    read_batt_mv()

    -- Wi-Fi
    wifi.setmode(wifi.STATION)
    if (not wifi.sta.config(wifiCfg)) then
        fail("Failed to configure wifi")
    end
    
    --    wifi.setmode(wifi.NULLMODE)
    wifi.eventmon.register(wifi.eventmon.STA_GOT_IP, wifi_connected_cb)
    wifi.eventmon.register(wifi.eventmon.STA_DHCP_TIMEOUT, wifi_fail_cb)

    -- Data Transmission
    mqClnt=mqtt.Client(mqttCfg.client, 20, mqttCfg.user, mqttCfg.pass)
    mqClnt:on("offline", mqtt_offline_cb)
    mqClnt:on("message", mqtt_message_cb)

end

switch_start()

