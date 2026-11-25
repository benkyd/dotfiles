return {
    -- LOOK
    {
        'rebelot/kanagawa.nvim',
        lazy = false,
        priority = 1000,
        config = function()
            require('kanagawa').setup({
                undercurl = true,
                commentStyle = { italic = true },
                keywordStyle = { italic = true },
                statementStyle = { bold = true },
            })
            vim.cmd.colorscheme('kanagawa')

            vim.keymap.set('n', '<leader>tt', function()
                if vim.o.background == 'dark' then
                    vim.o.background = 'light'
                    vim.cmd.colorscheme('kanagawa-lotus')
                else
                    vim.o.background = 'dark'
                    vim.cmd.colorscheme('kanagawa')
                end
            end, { desc = 'Toggle light/dark theme' })
        end,
    },
    {
        'jovanlanik/fsplash.nvim',
        opts = {
            lines = {
                "▄▄▄▄· ▄▄▄ . ▐ ▄  ▌ ▐·▪  • ▌ ▄ ·. ",
                "▐█ ▀█▪▀▄.▀·•█▌▐█▪█·█▌██ ·██ ▐███▪",
                "▐█▀▀█▄▐▀▀▪▄▐█▐▐▌▐█▐█•▐█·▐█ ▌▐▌▐█·",
                "██▄▪▐█▐█▄▄▌██▐█▌ ███ ▐█▌██ ██▌▐█▌",
                "·▀▀▀▀  ▀▀▀ ▀▀ █▪. ▀  ▀▀▀▀▀  █▪▀▀▀",
                '',
                'NVIM v' .. vim.version().major .. '.' .. vim.version().minor .. '.' .. vim.version().patch,
                'Nvim is open Source and freely distributable',
                '',
                'type  :checkhealth<Enter>     to optimize Nvim',
                'type  :q<Enter>               to exit         ',
                'type  :help<Enter>            for help        ',
                '',
                'type  :help news<Enter> to see changes in v'
                .. vim.version().major .. '.' .. vim.version().minor,
            },
            border = 'none',
        },
        config = function(_, opts)
            require('fsplash').setup(opts)
            vim.api.nvim_create_autocmd('VimEnter', {
                callback = function() require('fsplash').open_window() end,
            })
        end,
    },
    { 'benkyd/nvim-hardline', opts = {} },
    {
        'lukas-reineke/indent-blankline.nvim',
        main = 'ibl',
        opts = {
            debounce = 100,
            indent = { char = '│' },
            whitespace = { highlight = { 'Whitespace', 'NonText' } },
        },
    },
    { 'NvChad/nvim-colorizer.lua', opts = {} },

    -- GIT
    { 'tpope/vim-fugitive' },
    {
        'lewis6991/gitsigns.nvim',
        opts = {
            attach_to_untracked = true,
            current_line_blame_opts = { delay = 100 },
            current_line_blame_formatter = '<author>, <author_time:%Y-%m-%d> - <summary>',
            on_attach = function(bufnr)
                vim.keymap.set('n', '<leader>gb', require('gitsigns').toggle_current_line_blame,
                    { buffer = bufnr, desc = 'Toggle line blame' })
            end,
        },
    },

    -- FINDING THINGS
    {
        'nvim-telescope/telescope.nvim',
        dependencies = {
            'nvim-lua/plenary.nvim',
            'nvim-tree/nvim-web-devicons',
            'nvim-telescope/telescope-ui-select.nvim', -- code actions in a picker
        },
        config = function() require('plugin-config/telescope') end,
    },

    -- MOVING AROUND
    {
        'ThePrimeagen/harpoon',
        lazy = false,
        keys = {
            { '<leader>hh', function() require('harpoon.ui').toggle_quick_menu() end, desc = 'Harpoon menu' },
            { '<leader>hg', function() require('harpoon.mark').toggle_file() end, desc = 'Harpoon this file' },
        },
        config = function()
            require('harpoon').setup({ tabline = true })
            for pos = 1, 9 do
                vim.keymap.set('n', '<C-w>' .. pos, function() require('harpoon.ui').nav_file(pos) end,
                    { desc = 'Harpoon mark ' .. pos })
            end
        end,
    },
    {
        'yorickpeterse/nvim-window',
        keys = {
            { '<C-w>e', function() require('nvim-window').pick() end, desc = 'Jump to window' },
        },
        config = true,
    },
    {
        -- Tree you can edit like oil, in a float. Enter unfolds a folder in
        -- place; picking a file closes the float and opens it in your window
        'FylerOrg/fyler.nvim',
        lazy = false, -- it opens directories, e.g. `nvim .`
        dependencies = { 'nvim-tree/nvim-web-devicons' },
        keys = {
            { '<C-b>', function() require('fyler').toggle({ kind = 'floating' }) end, desc = 'File tree' },
        },
        opts = {
            follow_root_dir = false, -- don't change the working directory
            integrations = { icon = 'nvim_web_devicons' },
            extensions = { git = { enabled = true } },
            kind_presets = {
                floating = {
                    border = 'rounded',
                    mappings = {
                        n = {
                            ['<2-LeftMouse>'] = { action = 'select', args = { close = true, pick = false } },
                        },
                    },
                },
            },
        },
    },
    {
        'stevearc/oil.nvim',
        dependencies = { 'nvim-tree/nvim-web-devicons' },
        keys = {
            { '-', function() require('oil').open_float() end, desc = "Oil: this file's folder" },
        },
        opts = {
            default_file_explorer = false, -- fyler opens directories
            float = {
                max_width = 80,
                max_height = 20,
                border = 'rounded',
                win_options = { winblend = 0 },
            },
        },
    },

    -- EDITING
    {
        'nvim-treesitter/nvim-treesitter',
        branch = 'main',
        lazy = false,
        build = ':TSUpdate',
        dependencies = {
            { 'nvim-treesitter/nvim-treesitter-textobjects', branch = 'main' },
        },
        config = function() require('plugin-config/treesitter') end,
    },
    { 'nvim-treesitter/nvim-treesitter-context' },
    { 'windwp/nvim-autopairs', opts = {} },
    {
        'ntpeters/vim-better-whitespace',
        config = function()
            vim.keymap.set('n', '<leader>W', '<Cmd>StripWhitespace<CR>', { desc = 'Strip trailing whitespace' })
        end,
    },
    {
        -- Highlight other uses of the word under the cursor (snacks does the fade)
        'tzachar/local-highlight.nvim',
        dependencies = { { 'folke/snacks.nvim', opts = {} } },
        config = function()
            require('local-highlight').setup({
                hlgroup = 'Search',
                cw_hlgroup = nil,
                insert_mode = true,
                min_match_len = 1,
                max_match_len = math.huge,
                highlight_single_match = true,
            })
            vim.api.nvim_create_autocmd('BufRead', {
                pattern = { '*.*' },
                callback = function(data) require('local-highlight').attach(data.buf) end,
            })
        end,
    },
    { 'folke/which-key.nvim', event = 'VeryLazy', opts = {} },

    -- LANGUAGE SERVERS (servers and keys are in lua/lsp.lua)
    {
        'neovim/nvim-lspconfig',
        dependencies = { 'saghen/blink.cmp' },
        config = function() require('lsp') end,
    },
    {
        'saghen/blink.cmp',
        version = '1.*', -- release tags come with a prebuilt fuzzy matcher
        opts = {
            keymap = {
                preset = 'default', -- <C-y> accept, <C-e> close, <C-space> open
                ['<Tab>'] = { 'select_next', 'snippet_forward', 'fallback' },
                ['<S-Tab>'] = { 'select_prev', 'snippet_backward', 'fallback' },
            },
            completion = {
                list = { selection = { preselect = false, auto_insert = true } },
                documentation = { auto_show = true },
            },
            -- Snippets still come from the language servers, via vim.snippet
            sources = { default = { 'lsp', 'path', 'buffer' } },
            fuzzy = { implementation = 'prefer_rust_with_warning' },
        },
    },
    { 'j-hui/fidget.nvim', opts = {} }, -- language server progress
    {
        'stevearc/conform.nvim',
        keys = {
            { '<leader>F', function() require('conform').format({ lsp_format = 'fallback' }) end, desc = 'Format' },
        },
        opts = {
            formatters_by_ft = {
                c = { 'clang-format' },
                cpp = { 'clang-format' },
                rust = { 'rustfmt' },
                zig = { 'zigfmt' },
                lua = { 'stylua' },
                python = { 'black' },
                javascript = { 'prettier' },
                typescript = { 'prettier' },
                html = { 'prettier' },
                css = { 'prettier' },
                json = { 'prettier' },
                yaml = { 'prettier' },
            },
        },
    },

    -- LANGUAGES
    {
        -- Rust: owns rust-analyzer, so it isn't in lua/lsp.lua
        'mrcjkb/rustaceanvim',
        version = '^9',
        lazy = false, -- it loads itself for Rust files
        init = function()
            vim.g.rustaceanvim = {
                server = {
                    on_attach = function(_, bufnr)
                        local function map(lhs, rhs, desc)
                            vim.keymap.set('n', lhs, rhs, { buffer = bufnr, desc = desc })
                        end
                        map('<A-CR>', function() vim.cmd.RustLsp('codeAction') end, 'Rust code action')
                        map('J', function() vim.cmd.RustLsp('joinLines') end, 'Rust join lines')
                        map('<leader>Rr', function() vim.cmd.RustLsp('runnables') end, 'Rust runnables')
                        map('<leader>Rt', function() vim.cmd.RustLsp('testables') end, 'Rust testables')
                        map('<leader>Rl', function() vim.cmd.RustLsp({ 'runnables', bang = true }) end, 'Rerun last runnable')
                        map('<leader>Rm', function() vim.cmd.RustLsp('expandMacro') end, 'Expand macro')
                        map('<leader>Re', function() vim.cmd.RustLsp('explainError') end, 'Explain error')
                        map('<leader>RD', function() vim.cmd.RustLsp('renderDiagnostic') end, 'Render diagnostic')
                        map('<leader>Rc', function() vim.cmd.RustLsp('openCargo') end, 'Open Cargo.toml')
                        map('<leader>Rp', function() vim.cmd.RustLsp('parentModule') end, 'Parent module')
                        map('<leader>Ro', function() vim.cmd.RustLsp('openDocs') end, 'Open docs.rs')
                        map('<leader>Rh', function()
                            vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled({ bufnr = bufnr }), { bufnr = bufnr })
                        end, 'Toggle inlay hints')
                        vim.lsp.inlay_hint.enable(true, { bufnr = bufnr })
                    end,
                    default_settings = {
                        ['rust-analyzer'] = {
                            cargo = { allFeatures = true, buildScripts = { enable = true } },
                            check = { command = 'clippy' },
                            procMacro = { enable = true },
                            inlayHints = {
                                closureReturnTypeHints = { enable = 'with_block' },
                                lifetimeElisionHints = { enable = 'skip_trivial' },
                            },
                        },
                    },
                },
            }
        end,
    },
    {
        -- Cargo.toml: crate versions and features
        'saecki/crates.nvim',
        tag = 'stable',
        event = { 'BufRead Cargo.toml' },
        opts = {
            lsp = { enabled = true, actions = true, completion = true, hover = true },
        },
    },
    {
        'lervag/vimtex',
        lazy = false, -- vimtex loads itself for TeX files
        keys = {
            { '<leader>ll', '<Cmd>VimtexCompileSS<CR>', desc = 'Compile LaTeX' },
            { '<leader>lc', '<Cmd>VimtexCompile<CR>', desc = 'Compile LaTeX continuously' },
        },
        init = function()
            -- zathura on Linux; macOS uses the default viewer
            if vim.fn.has('mac') == 0 then vim.g.vimtex_view_method = 'zathura' end
        end,
    },
}
