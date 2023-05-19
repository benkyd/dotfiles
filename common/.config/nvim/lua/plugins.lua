local fn = vim.fn
local installPath = DATA_PATH..'/site/pack/packer/start/packer.nvim'

-- install packer if it's not installed already
local packerBootstrap = nil
if fn.empty(fn.glob(installPath)) > 0 then
    packerBootstrap = fn.system({'git', 'clone', '--depth', '1', 'https://github.com/wbthomason/packer.nvim', installPath})
    vim.cmd [[packadd packer.nvim]]
end


local packer = require('packer').startup(function(use)
    -- Packer should manage itself
    use 'wbthomason/packer.nvim'

    -- colourscheme
    use { 'rebelot/kanagawa.nvim' }
    use 'nvim-tree/nvim-web-devicons'

    -- QUALITY OF LIFE INTEGRATIONS

    -- git integration
    use 'tpope/vim-fugitive'

    use {
        'lewis6991/gitsigns.nvim',
        requires = { 'nvim-lua/plenary.nvim' },
        config = function ()
            require('plugin-config/gitsigns')
        end
    }

    -- colourise colour codes
    use {
        'norcalli/nvim-colorizer.lua',
        config = function ()
            require('colorizer').setup({})
        end
    }

    -- harpoon
    use {
        'ThePrimeagen/harpoon',
        config = function ()
            require('harpoon').setup({
                tabline = true,
            })
        end
    }

    -- telescope - searching / navigation
    use {
        'nvim-telescope/telescope.nvim',
        requires = {
            'nvim-lua/plenary.nvim',
            'nvim-telescope/telescope-ui-select.nvim',
            'debugloop/telescope-undo.nvim',
            'folke/todo-comments.nvim',
        },
        config = function ()
            require('plugin-config/telescope')
            require('todo-comments').setup({})
        end
    }

    -- better hotfix window (for showing and searching through results in telescope's find usages)
    use 'kevinhwang91/nvim-bqf'

    -- better highlighting
    use {
        'nvim-treesitter/nvim-treesitter',
        run = ':TSUpdate',
        config = function ()
            require('plugin-config/nvim-treesitter')
        end
    }
    use 'nvim-treesitter/nvim-treesitter-context'

    -- better split navigation
    use {
        'mrjones2014/smart-splits.nvim',
        config = function ()
            require('plugin-config/smart-splits')
        end
    }

    -- zen mode
    use {
        'folke/zen-mode.nvim',
        config = function()
            require('zen-mode').setup({})
        end
    }

    -- gorbit's codewindow
    use {
        'gorbit99/codewindow.nvim',
        config = function()
            local codewindow = require('codewindow')
            codewindow.setup()
            codewindow.apply_default_keybinds()
        end
    }

    -- nerd commenter
    use 'scrooloose/nerdcommenter'

    -- nice diagnostic pane on the bottom
    use {
        'folke/trouble.nvim',
        config = function ()
            require('plugin-config/lsp-trouble')
        end
    }

    -- vscode like LSP code previews
    use {
        "glepnir/lspsaga.nvim",
        opt = true,
        branch = "main",
        event = "LspAttach",
        config = function()
            require("lspsaga").setup({
                symbol_in_winbar = {
                    enable = false,
                },
                lightbulb = {
                    enable = false,
                },
                rename = {
                    whole_project = false,
                }
            })
        end,
    }

    -- whitespace pedantics
    use 'ntpeters/vim-better-whitespace'

    -- auto brace pairs vscode-style
    use {
        'windwp/nvim-autopairs',
        config = function()
            require('nvim-autopairs').setup({})
        end
    }

    -- obsidian!!!
    use {
        'epwalsh/obsidian.nvim',
        config = function()
            require('plugin-config/obsidian')
        end
    }

    -- VISUAL CHANGES

    -- nicer looking tab display
    use {
        'lukas-reineke/indent-blankline.nvim',
        config = function ()
            require('indent_blankline').setup {
                char = '│',
                filetype_exclude = { 'help', 'alpha', 'dashboard', 'neo-tree', 'Trouble', 'lazy' },
            }
        end
    }

    -- nicer looking indent guides
    use {
        'echasnovski/mini.indentscope',
        config = function ()
            require('mini.indentscope').setup({
                symbol = '│',
                options = { try_as_border = true },
            })
        end
    }

    -- colourcolumn that looks better
    use {
        'ecthelionvi/NeoColumn.nvim',
        config = function()
            require('NeoColumn').setup({
                NeoColumn = '80',
                always_on = true,
            })
        end
    }

    -- statusline
    use {
        'benkyd/nvim-hardline',
        config = function ()
            require('hardline').setup({})
        end
    }

    -- FUNCTIONAL CODING STUFF

    -- AI Autocompletion
    use {
        'zbirenbaum/copilot.lua',
        cmd = 'Copilot',
        event = 'InsertEnter',
        config = function()
            require('copilot').setup({
                suggestion = {
                    enabled = true,
                    auto_trigger = true,
                    keymap = {
                        accept = '<C-CR>',
                    }
                },
            })
        end
    }

    use {
        'VonHeikemen/lsp-zero.nvim',
        branch = 'v1.x',
        requires = {
            -- LSP Support
            {'neovim/nvim-lspconfig'},
            {'williamboman/mason.nvim'},
            {'williamboman/mason-lspconfig.nvim'},

            {'simrat39/rust-tools.nvim'},

            -- Autocompletion
            {'hrsh7th/nvim-cmp'},
            {'hrsh7th/cmp-nvim-lsp'},
            {'hrsh7th/cmp-nvim-lua'},
            {'hrsh7th/cmp-buffer'},
            {'hrsh7th/cmp-path'},
            {'hrsh7th/cmp-cmdline'},
            {'saadparwaiz1/cmp_luasnip'},

            -- Snippets
            {'L3MON4D3/LuaSnip'},
            {'rafamadriz/friendly-snippets'},
        },
        config = function ()
            require('lsp-general')
        end
    }

    -- for lsp signature autocompletion
    use {
        'ray-x/lsp_signature.nvim',
        config = function ()
            require('lsp_signature').setup({
                hint_prefix='🚀'
            })
        end
    }

    -- this will automatically install listed dependencies
    -- only the first time NeoVim is opened, because that's when Packer gets installed
    if packerBootstrap then
        require('packer').sync()
    end
end)

return packer
