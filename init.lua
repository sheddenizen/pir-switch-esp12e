function kick_off()
    dofile("switch.lua")
end

function abort()
    tmr.stop(0)
end

tmr.register(0, 2000, tmr.ALARM_SINGLE, kick_off)
tmr.start(0)
