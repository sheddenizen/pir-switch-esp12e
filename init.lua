function kick_off()
    dofile("pir.lua")
end

function abort()
    tmr.stop(0)
end

-- If sensor input is active, cut straight to the chase, otherwise wait to allow intervention
gpio.mode(6, gpio.INPUT)
if (gpio.read(6) == 1) then
    kick_off()
else
    tmr.register(0, 2000, tmr.ALARM_SINGLE, kick_off)
    tmr.start(0)
end
