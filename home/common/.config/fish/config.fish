if test -d /opt/homebrew/bin
    fish_add_path /opt/homebrew/bin/
end

if status is-interactive
    alias v 'nvim'
end
