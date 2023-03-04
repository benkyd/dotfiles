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

    -- colorscheme
    use { 'catppuccin/nvim', as = 'catppuccin' }
    use 'rebelot/kanagawa.nvim'
    use 'nvim-tree/nvim-web-devicons'

    -- QUALITY OF LIFE INTEGRATIONS

    -- git integration
    use {
        'lewis6991/gitsigns.nvim',
        requires = { 'nvim-lua/plenary.nvim' },
        config = function ()
            require('plugin-config/gitsigns')
        end
    }

    use 'tpope/vim-fugitive'

    -- speedy searching
    use {
        'ggandor/leap.nvim',
        config = function ()
            require('leap').add_default_mappings()
        end
    }

    -- telescope - searching / navigation
    use {
        'nvim-telescope/telescope.nvim',
        requires = {
            'nvim-lua/plenary.nvim',
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
    use({
        'dnlhc/glance.nvim',
        config = function()
            require('glance').setup({})
        end
    })
     
    -- VISUAL CHANGES

    -- start page
    use {
        'echasnovski/mini.starter',
        config = function ()
            require('plugin-config/ministarter')
        end
    }

    -- nicer looking tab display
    use {
        'lukas-reineke/indent-blankline.nvim',
        config = function ()
            require("indent_blankline").setup {
                char = "│",
                filetype_exclude = { "help", "alpha", "dashboard", "neo-tree", "Trouble", "lazy" },
            }
        end
    }

    use {
        'echasnovski/mini.indentscope',
        config = function ()
            require('mini.indentscope').setup {
                symbol = "│",
                options = { try_as_border = true },
            }
        end
    }

    -- statusline
    use {
        'ojroques/nvim-hardline',
        config = function ()
            require('hardline').setup({})
        end
    }

    -- UX improvements
    use {
        "folke/noice.nvim",
        requires = {
            "MunifTanjim/nui.nvim",
            "rcarriga/nvim-notify",
        },
        config = function ()
            require('plugin-config/noice')
        end
    }

    use {
        'stevearc/dressing.nvim',
        config = function ()
            require('plugin-config/dressing')
        end
    }

    use 'rcarriga/nvim-notify'


    -- FUNCTIONAL CODING STUFF

    -- lsp config
    use {
        "williamboman/mason.nvim",
        requires = {
            "williamboman/mason-lspconfig.nvim",
            "neovim/nvim-lspconfig",
        },
    }

    -- for LSP autocompletion
    use {
        'hrsh7th/nvim-cmp',
        requires = {
            'hrsh7th/cmp-nvim-lsp',
            'hrsh7th/cmp-buffer',
            'hrsh7th/cmp-path',
            'hrsh7th/cmp-cmdline',
        },
        config = function ()
            require('plugin-config/nvim-cmp')
        end
    }

    -- for lsp signature autocompletion
    use {
        'ray-x/lsp_signature.nvim',
        config = function ()
            require('lsp_signature').setup()
        end
    }

    -- this will automatically install listed dependencies
    -- only the first time NeoVim is opened, because that's when Packer gets installed
    if packerBootstrap then
        require('packer').sync()
    end
end)

return packer
