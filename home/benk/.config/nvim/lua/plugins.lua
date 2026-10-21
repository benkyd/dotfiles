return {
    {
        'rebelot/kanagawa.nvim',
        lazy = false,
        priority = 1000,
        config = function()
            require('kanagawa').setup({
                undercurl = true,
                commentStyle = { italic = true },
                keywordsStyle = { italic = true },
                statementStyle = { bold = true },
            })
            vim.cmd('colorscheme kanagawa')
            -- Transparent bg so catppuccin mocha terminal bg shows through
            vim.api.nvim_set_hl(0, 'Normal', { bg = 'none' })
            vim.api.nvim_set_hl(0, 'NormalFloat', { bg = 'none' })

            vim.keymap.set('n', '<leader>tt', function()
                if vim.o.background == 'dark' then
                    vim.o.background = 'light'
                    vim.cmd('colorscheme kanagawa-lotus')
                else
                    vim.o.background = 'dark'
                    vim.cmd('colorscheme kanagawa')
                    vim.api.nvim_set_hl(0, 'Normal', { bg = 'none' })
                    vim.api.nvim_set_hl(0, 'NormalFloat', { bg = 'none' })
                end
            end, { desc = 'Toggle light/dark theme' })
        end
    },
    -- QUALITY OF LIFE INTEGRATIONS
    {
        'tpope/vim-fugitive',
    },
    {
        'hat0uma/csvview.nvim',
        lazy = true,
    },
    {
        'folke/snacks.nvim',
        lazy = false,
    },
    {
        'tzachar/local-highlight.nvim',
        config = function()
            require('local-highlight').setup({
                hlgroup = 'Search',
                cw_hlgroup = nil,
                -- Whether to display highlights in INSERT mode or not
                insert_mode = true,
                min_match_len = 1,
                max_match_len = math.huge,
                highlight_single_match = true,
            })
            vim.api.nvim_create_autocmd('BufRead', {
                pattern = {'*.*'},
                callback = function(data)
                    require('local-highlight').attach(data.buf)
                end
            })
        end
    },
    {
        'lewis6991/gitsigns.nvim',
        config = function()
            require('plugin-config/gitsigns')
        end
    },
    {
        -- Window picker
        "yorickpeterse/nvim-window",
        keys = {
            { "<C-w>e", "<cmd>lua require('nvim-window').pick()<cr>", desc = "nvim-window: Jump to window" },
        },
        config = true,
    },
    {
        -- colourise colour codes
        'NvChad/nvim-colorizer.lua',
        lazy = false,
        opts = {}
    },
    {
        -- Vim vinegar - better netrw
        'stevearc/oil.nvim',
        opts = {
            float = {
                max_width = 80,
                max_height = 20,
                border = 'rounded',
                win_options = {
                    winblend = 0,
                },
            },
        },
        keys = {
            { '<C-b>', '<cmd>lua require("oil").open_float()<cr>', desc = "Toggle Oil" },
        },
        -- Optional dependencies
        dependencies = { "nvim-tree/nvim-web-devicons" }
    },
    {
        -- EPIC HARPOON MOMENT
        'ThePrimeagen/harpoon',
        lazy = false,
        keys = {
            { '<leader>hh', '<cmd>lua require("harpoon.ui").toggle_quick_menu()<cr>', desc = "Toggle harpoon menu" },
            { '<leader>hg', '<cmd>lua require("harpoon.mark").toggle_file() <cr>',    desc = "Add file to harpoon list" },
        },
        config = function()
            require('harpoon').setup({ tabline = true })

            for pos = 1, 9 do
                vim.keymap.set("n", "<C-w>" .. pos, function()
                    require("harpoon.ui").nav_file(pos)
                end, { desc = "Move to harpoon mark #" .. pos })
            end
        end
    },
    {
        'nvim-telescope/telescope.nvim',
        dependencies = {
            'nvim-tree/nvim-web-devicons',
            'nvim-lua/plenary.nvim',
            'nvim-telescope/telescope-ui-select.nvim',
            'debugloop/telescope-undo.nvim',
            'folke/todo-comments.nvim',
            'kevinhwang91/nvim-bqf',
            'rcarriga/nvim-notify',
        },
        config = function()
            require('plugin-config/telescope')
            require('todo-comments').setup({})
        end
    },
    {
        'nvim-treesitter/nvim-treesitter',
        branch = 'main',
        lazy = false,
        build = ':TSUpdate',
        dependencies = {
            -- Treesitter text objects (select/move by function, class, parameter)
            { 'nvim-treesitter/nvim-treesitter-textobjects', branch = 'main' },
        },
        config = function()
            require('plugin-config/nvim-treesitter')
        end
    },
    {
        'nvim-treesitter/nvim-treesitter-context',
        dependencies = { 'nvim-treesitter/nvim-treesitter' },
    },
    {
        'mrjones2014/smart-splits.nvim',
        config = function()
            require('plugin-config/smart-splits')
        end
    },
    {
        'folke/zen-mode.nvim',
        lazy = true,
        opts = {},
        keys = {
            { '<leader>z', '<cmd>lua require("zen-mode").toggle()<cr>', desc = "Toggle zen mode" },
        },
    },
    {
        'gorbit99/codewindow.nvim',
        lazy = false,
        dependencies = { 'nvim-treesitter/nvim-treesitter' },
        init = function()
            -- codewindow still requires nvim-treesitter.ts_utils, which the
            -- treesitter main branch removed; shim the one function it uses
            package.preload['nvim-treesitter.ts_utils'] = function()
                return {
                    get_vim_range = function(range, buf)
                        local srow, scol, erow, ecol = unpack(range)
                        srow, scol, erow = srow + 1, scol + 1, erow + 1
                        if ecol == 0 then
                            erow = erow - 1
                            if not buf or buf == 0 then
                                ecol = vim.fn.col({ erow, '$' }) - 1
                            else
                                ecol = #vim.api.nvim_buf_get_lines(buf, erow - 1, erow, false)[1]
                            end
                            ecol = math.max(ecol, 1)
                        end
                        return srow, scol, erow, ecol
                    end,
                }
            end
        end,
        config = function()
            require('codewindow').apply_default_keybinds()
        end
    },
    {
        'numToStr/Comment.nvim',
        opts = {
            padding = true,
            toggler = {
                line = '<leader>cc',
                block = '<leader>bb',
            },
            opleader = {
                line = '<leader>c',
                block = '<leader>b',
            },
            extra = {
                above = '<leader>cO',
                below = '<leader>co',
                eol = '<leader>ca',
            },
            mappings = {
                basic = true,
                extra = true,
            },
        },
    },
    {
        'glepnir/lspsaga.nvim',
        lazy = false,
        opts = {
            symbol_in_winbar = {
                enable = false,
            },
            lightbulb = {
                enable = false,
            },
            rename = {
                whole_project = false,
            }
        },
    },
    {
        'ntpeters/vim-better-whitespace'
    },
    {
        'windwp/nvim-autopairs',
        opts = {},
    },
    -- VISUAL CHANGES
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
                'NVIM v'
                .. vim.version().major
                .. '.'
                .. vim.version().minor
                .. '.'
                .. vim.version().patch,
                'Nvim is open Source and freely distributable',
                '',
                'type  :checkhealth<Enter>     to optimize Nvim',
                'type  :q<Enter>               to exit         ',
                'type  :help<Enter>            for help        ',
                '',
                'type  :help news<Enter> to see changes in v'
                .. vim.version().major
                .. '.'
                .. vim.version().minor
            },
            border = 'none',
        },
    },
    {
        'lukas-reineke/indent-blankline.nvim',
        main = 'ibl',
        opts = {
            debounce = 100,
            indent = { char = '│' },
            whitespace = { highlight = { "Whitespace", "NonText" } },
        }
    },
    {
        'echasnovski/mini.indentscope',
        opts = {
            symbol = '│',
            options = { try_as_border = true },
        },
    },
    {
        'ecthelionvi/NeoColumn.nvim',
        opts = {
            NeoColumn = '80',
            always_on = true,
        },
    },
    {
        'benkyd/nvim-hardline',
        opts = {},
    },
    -- FUNCTIONAL CODING STUFF
    {
        "L3MON4D3/LuaSnip",
        build = "make install_jsregexp"
    },
    {
        'neovim/nvim-lspconfig',
        dependencies = {
            { 'nvim-neotest/nvim-nio' },
            { 'mfussenegger/nvim-dap' },

            -- Autocompletion
            { 'hrsh7th/nvim-cmp' },
            { 'hrsh7th/cmp-nvim-lsp' },
            { 'hrsh7th/cmp-nvim-lua' },
            { 'hrsh7th/cmp-buffer' },
            { 'hrsh7th/cmp-path' },
            { 'hrsh7th/cmp-cmdline' },
            { 'saadparwaiz1/cmp_luasnip' },

            -- Snippets
            { 'rafamadriz/friendly-snippets' },
        },
        config = function()
            require('lsp-general')
        end
    },
    {
        'ray-x/lsp_signature.nvim',
        opts = {
            hint_prefix = '🚀'
        },
    },
    {
        'rcarriga/nvim-dap-ui',
        dependencies = {
            'mfussenegger/nvim-dap',
        },
        keys = {
            { '<leader>db', '<cmd>lua require("dap").toggle_breakpoint()<cr>', desc = "Toggle DAP UI" },
            { '<leader>dc', '<cmd>lua require("dap").continue()<cr>' },
            { '<leader>dn', '<cmd>lua require("dap").step_over()<cr>' },
            { '<leader>di', '<cmd>lua require("dap").step_into()<cr>' },
            { '<leader>do', '<cmd>lua require("dap").step_out()<cr>' },
        },
        lazy = false
    },
    {
        "lervag/vimtex",
        lazy = false,
        keys = {
            { '<leader>ll', '<cmd>VimtexCompileSS<cr>', desc = "Compile LaTeX" },
            { '<leader>lc', '<cmd>VimtexCompile<cr>',   desc = "Compile LaTeX Continuously" },
        },
        config = function()
            vim.g.vimtex_view_method = 'zathura'
        end,
    },
    -- Rust (replaces rust-tools.nvim). Owns rust-analyzer, don't vim.lsp.enable it.
    -- Needs `rustup component add rust-analyzer`; debugging needs codelldb or lldb-dap.
    {
        'mrcjkb/rustaceanvim',
        version = '^9',
        lazy = false, -- it lazy-loads itself on ft=rust
        init = function()
            vim.g.rustaceanvim = {
                server = {
                    on_attach = function(_, bufnr)
                        local function map(lhs, rhs, desc)
                            vim.keymap.set('n', lhs, rhs, { buffer = bufnr, desc = desc })
                        end
                        -- grouped code actions (rust-analyzer specific)
                        map('<A-CR>', function() vim.cmd.RustLsp('codeAction') end, 'Rust code action')
                        map('J', function() vim.cmd.RustLsp('joinLines') end, 'Rust join lines')
                        map('<leader>Rr', function() vim.cmd.RustLsp('runnables') end, 'Rust runnables')
                        map('<leader>Rt', function() vim.cmd.RustLsp('testables') end, 'Rust testables')
                        map('<leader>Rd', function() vim.cmd.RustLsp('debuggables') end, 'Rust debuggables')
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
    -- Cargo.toml: crate versions, features, completion via in-process LSP
    {
        'saecki/crates.nvim',
        tag = 'stable',
        event = { 'BufRead Cargo.toml' },
        opts = {
            lsp = {
                enabled = true,
                actions = true,
                completion = true,
                hover = true,
            },
        },
    },
    -- LSP progress indicator
    {
        'j-hui/fidget.nvim',
        opts = {},
    },
    -- Format on save / manual format (clang-format, prettier, etc.)
    {
        'stevearc/conform.nvim',
        opts = {
            formatters_by_ft = {
                c = { 'clang-format' },
                cpp = { 'clang-format' },
                javascript = { 'prettier' },
                typescript = { 'prettier' },
                html = { 'prettier' },
                css = { 'prettier' },
                json = { 'prettier' },
                yaml = { 'prettier' },
                lua = { 'stylua' },
                python = { 'black' },
                rust = { 'rustfmt' },
            },
        },
    },
    -- Better diff/merge UI
    {
        'sindrets/diffview.nvim',
        keys = {
            { '<leader>gd', '<cmd>DiffviewOpen<cr>', desc = 'Open diffview' },
            { '<leader>gh', '<cmd>DiffviewFileHistory %<cr>', desc = 'File history' },
            { '<leader>gq', '<cmd>DiffviewClose<cr>', desc = 'Close diffview' },
        },
    },
    -- Keybinding cheat sheet
    {
        'folke/which-key.nvim',
        event = 'VeryLazy',
        opts = {},
    },

}
