# My Linux PC's monitor layout (KDE). Loaded automatically by fish from conf.d/.
function svm --description 'lock the session and turn the monitors off'
    loginctl lock-session
    kscreen-doctor \
        output.DP-3.disable \
        output.DP-4.disable \
        output.HDMI-A-5.disable
end

function dtm --description 'turn the monitors back on with the desktop layout'
    kscreen-doctor \
        output.DP-3.enable \
        output.DP-4.enable \
        output.HDMI-A-5.enable
    sleep 1
    kscreen-doctor \
        output.DP-3.mode.2 \
        output.DP-3.scale.0.75 \
        output.DP-3.position.2727,0 \
        output.DP-4.mode.49 \
        output.DP-4.scale.1 \
        output.DP-4.position.2160,1440 \
        output.HDMI-A-5.mode.114 \
        output.HDMI-A-5.scale.1 \
        output.HDMI-A-5.position.0,297 \
        output.HDMI-A-5.rotation.left
end
