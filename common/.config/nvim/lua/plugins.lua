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
        config = require('plugin-config/gitsigns'),
    }

    use 'tpope/vim-fugitive'

    -- speedy searching
    use {
        'ggandor/leap.nvim',
        config = require('leap').add_default_mappings(),
    }

    -- telescope - searching / navigation
    use {
        'nvim-telescope/telescope.nvim',
        requires = { 'nvim-lua/plenary.nvim' },
        config = require('plugin-config/telescope'),
    }

    -- better hotfix window (for showing and searching through results in telescope's find usages)
    use 'kevinhwang91/nvim-bqf'

    -- better highlighting
    use {
        'nvim-treesitter/nvim-treesitter', 
        run = ':TSUpdate',
        config = require('plugin-config/nvim-treesitter'),
    }
    use 'nvim-treesitter/nvim-treesitter-context'

    -- better split navigation
    use {
        'mrjones2014/smart-splits.nvim',
        config = require('plugin-config/smart-splits'),
    } 
    -- gorbit's codewindow 
    use {
        'gorbit99/codewindow.nvim',
        config = function()
            local codewindow = require('codewindow')
            codewindow.setup()
            codewindow.apply_default_keybinds()
        end,
    }

    -- nerd commenter
    use 'scrooloose/nerdcommenter'

    -- nice diagnostic pane on the bottom
    use {
        'folke/trouble.nvim',
        config = require('plugin-config/lsp-trouble'),
    }

    -- better LSP UI (for code actions, rename etc.)
    use {
        "glepnir/lspsaga.nvim",
        branch = "main",
        config = require('plugin-config/lspsaga'),
    }

    -- better find and replace
    use 'windwp/nvim-spectre'


    -- VISUAL CHANGES

    -- start page
    use {
        'echasnovski/mini.starter',
        config = require('plugin-config/ministarter'),
    }

    -- nicer looking tab display
    use {
        'lukas-reineke/indent-blankline.nvim',
        config = require("indent_blankline").setup {
            char = "│",
            filetype_exclude = { "help", "alpha", "dashboard", "neo-tree", "Trouble", "lazy" },
        },
    }

    use {
        'echasnovski/mini.indentscope',
        require('mini.indentscope').setup {
            symbol = "│",
            options = { try_as_border = true },
        },
    }

    -- statusline
    use {
        'ojroques/nvim-hardline',
        require('hardline').setup({}),
    }

    -- UX improvements
    use {
        "folke/noice.nvim",
        requires = {
            "MunifTanjim/nui.nvim",
            "rcarriga/nvim-notify",
        },
        config = require('plugin-config/noice')
    }

    use {
        'stevearc/dressing.nvim',
        config = require('plugin-config/dressing'),
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
        config = require('plugin-config/nvim-cmp'),
    } 

    -- this will automatically install listed dependencies
    -- only the first time NeoVim is opened, because that's when Packer gets installed
    if packerBootstrap then
        require('packer').sync()
    end
end)

return packer
