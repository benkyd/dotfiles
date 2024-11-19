return {
    {
        'rebelot/kanagawa.nvim',
        lazy = false,
        priority = 1000,
        config = function()
            vim.cmd('colorscheme kanagawa')
        end
    },
    -- QUALITY OF LIFE INTEGRATIONS
    {
        'tpope/vim-fugitive',
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
        'miversen33/sunglasses.nvim',
        config = function()
            require('sunglasses').setup({
                    filter_type = "SHADE",
                    filter_percent = .20
            })
        end   
    },
    {
        'lewis6991/gitsigns.nvim',
        dependencies = { 'nvim-lua/plenary.nvim' },
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
        'norcalli/nvim-colorizer.lua',
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
        'nvim-treesitter/nvim-treesitter-context',
        build = ':TSUpdate',
        dependencies = {
            'nvim-treesitter/nvim-treesitter',
        },
        config = function()
            require('plugin-config/nvim-treesitter')
        end
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
        opts = {},
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
        'zbirenbaum/copilot.lua',
        event = 'InsertEnter',
        opts = {
            suggestion = {
                enabled = true,
                auto_trigger = true,
                keymap = {
                    accept = '<C-y>',
                }
            },
        }
    },
    {
        "L3MON4D3/LuaSnip",
        -- follow latest release.
        version = "v2.*", -- Replace <CurrentMajor> by the latest released major (first number of latest release)
        -- install jsregexp (optional!).
        build = "make install_jsregexp"
    },
    {
        'VonHeikemen/lsp-zero.nvim',
        branch = 'v1.x',
        dependencies = {
            -- LSP Support
            { 'nvim-neotest/nvim-nio' },
            { 'neovim/nvim-lspconfig' },
            { 'williamboman/mason.nvim' },
            { 'mfussenegger/nvim-dap' },
            { 'jay-babu/mason-nvim-dap.nvim' },
            { 'williamboman/mason-lspconfig.nvim' },

            { 'simrat39/rust-tools.nvim' },

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
    {
        url = 'https://git.sr.ht/~whynothugo/lsp_lines.nvim',
        config = function()
            require('lsp_lines').setup()
            vim.keymap.set('', '<leader>x', function()
                local config = vim.diagnostic.config()
                vim.diagnostic.config({
                    virtual_text = not config.virtual_text,
                    virtual_lines = not config.virtual_lines,
                })
            end, { desc = 'Toggle Line Diagnostics' })

            vim.diagnostic.config({
                virtual_text = true,
                virtual_lines = false,
            })
        end,
    }

}
