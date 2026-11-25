-- The BENVIM splash, with some aura: a gradient drifting across the logo,
-- stars twinkling around it and a pulsing star under it. fsplash draws the
-- float and closes it on the first keypress; this adds the colour and motion.

local fsplash = require('fsplash')

vim.opt.shortmess:append('I') -- hide Neovim's own intro screen; this replaces it

-- kanagawa colours; sakura pink is the star of the show
local c = {
    pink = '#D27E99', violet = '#957FB8', white = '#DCD7BA', grey = '#727169', dim = '#54546D',
}

local logo = {
    '▄▄▄▄· ▄▄▄ . ▐ ▄  ▌ ▐·▪  • ▌ ▄ ·. ',
    '▐█ ▀█▪▀▄.▀·•█▌▐█▪█·█▌██ ·██ ▐███▪',
    '▐█▀▀█▄▐▀▀▪▄▐█▐▐▌▐█▐█•▐█·▐█ ▌▐▌▐█·',
    '██▄▪▐█▐█▄▄▌██▐█▌ ███ ▐█▌██ ██▌▐█▌',
    '·▀▀▀▀  ▀▀▀ ▀▀ █▪. ▀  ▀▀▀▀▀  █▪▀▀▀',
}
local v = vim.version()
local divider = '─────────── ✦ ───────────'
local about = {
    ('NVIM v%d.%d.%d'):format(v.major, v.minor, v.patch),
    'Nvim is open Source and freely distributable',
}
local help = {
    'type  :checkhealth<Enter>     to optimize Nvim',
    'type  :q<Enter>               to exit',
    'type  :help<Enter>            for help',
    '',
    ('type  :help news<Enter> to see changes in v%d.%d'):format(v.major, v.minor),
}

-- Lay it out: each group centred as a block, with a margin for the stars
local margin = 7
local width = 0
for _, group in ipairs({ logo, { divider }, about, help }) do
    for _, line in ipairs(group) do width = math.max(width, vim.fn.strdisplaywidth(line)) end
end
width = width + 2 * margin

local lines, rows = {}, {}
local function add(group, name, centre_each)
    local block = 0
    for _, line in ipairs(group) do block = math.max(block, vim.fn.strdisplaywidth(line)) end
    for _, line in ipairs(group) do
        local w = centre_each and vim.fn.strdisplaywidth(line) or block
        local pad = math.floor((width - w) / 2)
        table.insert(lines, (' '):rep(pad) .. line .. (' '):rep(width - pad - vim.fn.strdisplaywidth(line)))
        table.insert(rows, { kind = name, pad = pad })
    end
end
local function gap() add({ '' }, 'gap') end

gap() -- fsplash sizes the window from the first line's byte length, so keep it plain
gap()
add(logo, 'logo')
gap()
add({ divider }, 'divider', true)
gap()
add(about, 'about', true)
gap()
add(help, 'help')
gap()

fsplash.setup({ lines = lines, width = width, border = 'none' })

-- A looping gradient for the logo: kanagawa's sakura pink, with a pale glint
-- sweeping across it and a deeper rose band behind
local function mix(a, b, t)
    local function ch(hex, i) return tonumber(hex:sub(i, i + 1), 16) end
    local out = '#'
    for i = 2, 6, 2 do out = out .. ('%02x'):format(math.floor(ch(a, i) + (ch(b, i) - ch(a, i)) * t + 0.5)) end
    return out
end
local glow, glint, rose = mix(c.pink, c.white, 0.45), mix(c.pink, '#FFFFFF', 0.8), mix(c.pink, c.violet, 0.55)
local stops = { c.pink, c.pink, c.pink, glow, glint, glow, c.pink, c.pink, rose, rose }
local steps = 48
for i = 0, steps - 1 do
    local pos = i / steps * #stops
    local from = math.floor(pos)
    vim.api.nvim_set_hl(0, 'BenvimAura' .. i, {
        fg = mix(stops[from + 1], stops[(from + 1) % #stops + 1], pos - from), bold = true,
    })
end
vim.api.nvim_set_hl(0, 'BenvimVersion', { fg = c.white, bold = true })
vim.api.nvim_set_hl(0, 'BenvimTagline', { fg = c.grey, italic = true })
vim.api.nvim_set_hl(0, 'BenvimHelp', { fg = c.grey })
vim.api.nvim_set_hl(0, 'BenvimKey', { fg = c.pink })
vim.api.nvim_set_hl(0, 'BenvimRule', { fg = c.dim })
vim.api.nvim_set_hl(0, 'BenvimStarDim', { fg = c.dim })
vim.api.nvim_set_hl(0, 'BenvimStarMid', { fg = rose })
vim.api.nvim_set_hl(0, 'BenvimStarBright', { fg = glint, bold = true })

-- Byte ranges of each character, so multi-byte glyphs get highlighted whole
local function chars(line)
    local out, i = {}, 1
    while i <= #line do
        local len = vim.str_utf_end(line, i) + 1
        table.insert(out, { from = i - 1, to = i - 1 + len, text = line:sub(i, i + len - 1) })
        i = i + len
    end
    return out
end

-- Star spots: blank cells in the margins and gaps, picked the same way each time
local stars = {}
do
    local spots, seed = {}, 7
    for r, line in ipairs(lines) do
        for col = 1, width do
            local in_margin = col <= margin - 1 or col > width - margin + 1
            if line:sub(col, col) == ' ' and (in_margin or rows[r].kind == 'gap') and #line == width then
                table.insert(spots, { row = r - 1, col = col - 1 })
            end
        end
    end
    for i = 1, math.min(18, #spots) do
        seed = (seed * 1103515245 + 12345) % 2147483648
        local spot = table.remove(spots, seed % #spots + 1)
        spot.phase = seed % 60
        table.insert(stars, spot)
    end
end
local twinkle = { -- frames into a star's cycle → look; it rests unseen the rest of the time
    [0] = { '·', 'BenvimStarDim' }, { '·', 'BenvimStarMid' }, { '✧', 'BenvimStarMid' },
    { '✦', 'BenvimStarBright' }, { '✦', 'BenvimStarBright' }, { '✧', 'BenvimStarMid' },
    { '·', 'BenvimStarMid' }, { '·', 'BenvimStarDim' },
}

local ns = vim.api.nvim_create_namespace('benvim-splash')

local function hl(buf, row, from, to, group)
    vim.api.nvim_buf_set_extmark(buf, ns, row, from, { end_col = to, hl_group = group })
end

local function draw(buf, frame)
    vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    for r, line in ipairs(lines) do
        local row, kind = r - 1, rows[r].kind
        if kind == 'logo' then
            local logo_row = row - 2
            for col, ch in ipairs(chars(line)) do
                if ch.text ~= ' ' then
                    local shade = (col - rows[r].pad + logo_row * 2 - frame) % steps
                    hl(buf, row, ch.from, ch.to, 'BenvimAura' .. shade)
                end
            end
        elseif kind == 'divider' then
            for _, ch in ipairs(chars(line)) do
                if ch.text == '✦' then
                    hl(buf, row, ch.from, ch.to, 'BenvimAura' .. (frame * 2) % steps)
                elseif ch.text ~= ' ' then
                    hl(buf, row, ch.from, ch.to, 'BenvimRule')
                end
            end
        elseif kind == 'about' then
            hl(buf, row, 0, #line, line:find('NVIM', 1, true) and 'BenvimVersion' or 'BenvimTagline')
        elseif kind == 'help' and line:find('%S') then
            hl(buf, row, 0, #line, 'BenvimHelp')
            for from, to in line:gmatch('():[%w ]-<Enter>()') do hl(buf, row, from - 1, to - 1, 'BenvimKey') end
        end
    end
    for _, star in ipairs(stars) do
        local look = twinkle[(frame + star.phase) % 60]
        if look then
            vim.api.nvim_buf_set_extmark(buf, ns, star.row, star.col,
                { virt_text = { look }, virt_text_pos = 'overlay' })
        end
    end
end

local function open()
    fsplash.open_window()
    local buf, win = fsplash.buffer, fsplash.window
    if not (buf and win) then return end

    local frame = 0
    draw(buf, frame)
    local timer = vim.uv.new_timer()
    timer:start(70, 70, vim.schedule_wrap(function()
        -- fsplash closes the window on the first keypress, move or resize
        if fsplash.window ~= win or not vim.api.nvim_win_is_valid(win) or not vim.api.nvim_buf_is_valid(buf) then
            timer:stop()
            if not timer:is_closing() then timer:close() end
            return
        end
        frame = frame + 1
        draw(buf, frame)
    end))
end

vim.api.nvim_create_autocmd('VimEnter', { callback = open })
