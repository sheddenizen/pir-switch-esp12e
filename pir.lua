require("config")

sens_state = 0;
monitor_count = 0;
battMv = 0;
battMvNumer = 5283
battMvDenom =1024
battConserveMv = 3300
battProtectMv = 3000
sleep_secs = 600
monitor_cycle_period_ms = 100

monitor_delay_cycles = 100

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
    battMv = adc.read(0) * battMvNumer / battMvDenom
end

function xmit_cleanup()
    wifi.sta.disconnect()
    wifi.setmode(wifi.NULLMODE)
    -- Sleep 60s for now
    info("Batt: "..battMv)
    info("Sleepy time")
    info("Sleepy time")
    rtctime.dsleep(sleep_secs * 1000000, 4)
end

function mqtt_finish(client)
    mqClnt:close()
    tmr.stop(1)
    tmr.unregister(1)
    tmr.register(1, 200, tmr.ALARM_SINGLE, xmit_cleanup)
    tmr.start(1)
end

function monitor()

    local sens_now = gpio.read(6)
    monitor_count = monitor_count+1;

    if (sens_now == sens_state) then
        read_batt_mv()
        -- Keep polling for 10s after last change
        if (monitor_count >= monitor_delay_cycles or battMv < battConserveMv) then
            mqtt_finish()
        else
            -- 100ms polling
            tmr.register(0, monitor_cycle_period_ms, tmr.ALARM_SINGLE, monitor)
            tmr.start(0)
        end
    else
        sens_state = sens_now
        monitor_count = 0
        info("Sensor: "..sens_state)
        mqClnt:publish(mqttCfg.sensorTopic, sens_state, 1, 0, monitor)
    end
end

function send_batt()
    info("sent state, sending batt")
    -- Send battery level, QoS 1, retain
    mqClnt:publish(mqttCfg.battTopic, battMv, 1, 1, monitor)
end

function mqtt_connect_cb(client)
    info("mqtt connected, send state")
    -- Send sensor state, QoS 1, don't retain
    mqClnt:publish(mqttCfg.sensorTopic, sens_state, 1, 0, send_batt)
end

function wifi_connected_cb(tbl)
    info("wifi connected"..cjson.encode(tbl))
    mqClnt:connect(mqttCfg.broker, mqttCfg.port, 0, 0, mqtt_connect_cb, mqtt_fail_cb)
end

function wifi_fail_cb(tbl)
    fail("wifi failed: "..cjson.encode(tbl))
    xmit_cleanup()
end

function mqtt_fail_cb(client, reason)
    fail("mqtt failed, reason: "..reason)
    xmit_cleanup()
end

function mqtt_offline_cb(client)
    info("mqtt offline, reason: ")
    xmit_cleanup()
end

function pir_start()

    -- Inhibit reset from sensor pin
    gpio.mode(5, gpio.OUTPUT)
    gpio.write(5, gpio.LOW)

    -- Get initial sensor input state
    gpio.mode(6, gpio.INPUT)
    sens_state = gpio.read(6)
    info("Sensor: "..sens_state)

    -- Init and set ADC input.
    adc.force_init_mode(adc.INIT_ADC)

    -- Get battery voltage
    read_batt_mv()
    info("Batt: "..battMv)
    if (battMv < battProtectMv) then
        fail("Can't transmit, battery low at "..battMv)
        xmit_cleanup();
    end
    -- Don't stay awake to monitor unless woken by sensor and batt healthy
    if (not sens_state) then
        monitor_count = 99
    end

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

end

pir_start()

