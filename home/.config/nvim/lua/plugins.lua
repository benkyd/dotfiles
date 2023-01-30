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

  -- QUALITY OF LIFE INTEGRATIONS

  -- git integration
  use {
    'lewis6991/gitsigns.nvim',
    requires = {
      'nvim-lua/plenary.nvim'
    }
  }

  -- telescope - searching / navigation
  use {
    'nvim-telescope/telescope.nvim',
    requires = { {'nvim-lua/plenary.nvim'} }
  }

  -- better hotfix window (for showing and searching through results in telescope's find usages)
  use {"kevinhwang91/nvim-bqf"}

  -- better highlighting
  use {'nvim-treesitter/nvim-treesitter', run = ':TSUpdate'}

  -- gorbit's codewindow 
  use {
    'gorbit99/codewindow.nvim',
    config = function()
      local codewindow = require('codewindow')
      codewindow.setup()
      codewindow.apply_default_keybinds()
    end,
  }
  -- surround vim
  use 'tpope/vim-surround'

  -- nerd commenter
  use 'scrooloose/nerdcommenter'

  -- nice diagnostic pane on the bottom
  use 'folke/lsp-trouble.nvim'

  -- support the missing lsp diagnostic colors
  use 'folke/lsp-colors.nvim'

  -- better LSP UI (for code actions, rename etc.)
  use 'tami5/lspsaga.nvim'

  -- better find and replace
  use 'nvim-lua/plenary.nvim'
  use 'windwp/nvim-spectre'

  -- VISUAL CHANGES

  -- start page
  use 'echasnovski/mini.starter'

  -- status line
  use 'glepnir/galaxyline.nvim'

  -- colorscheme
  use { 'catppuccin/nvim', as = 'catppuccin' }

  -- nicer looking tab display
  use 'lukas-reineke/indent-blankline.nvim'
  use 'echasnovski/mini.indentscope'

  -- show startup time
  use 'dstein64/vim-startuptime'

  use 'kyazdani42/nvim-web-devicons'

  -- UX improvements
  use({
    "folke/noice.nvim",
    requires = {
      "MunifTanjim/nui.nvim",
      "rcarriga/nvim-notify",
    }
  })

  use 'stevearc/dressing.nvim'

  use 'rcarriga/nvim-notify'

  -- FUNCTIONAL CODING STUFF

  -- lsp config
  use {
    'neovim/nvim-lspconfig',
    'williamboman/nvim-lsp-installer',
  }

  -- for LSP autocompletion
  use 'hrsh7th/cmp-nvim-lsp'
  use 'hrsh7th/cmp-buffer'
  use 'hrsh7th/cmp-path'
  use 'hrsh7th/cmp-cmdline'
  use 'hrsh7th/nvim-cmp'

  -- For vsnip users.
  use 'hrsh7th/cmp-vsnip'
  use 'hrsh7th/vim-vsnip'

  -- highlight variables under cursor
  use 'RRethy/vim-illuminate'

  -- this will automatically install listed dependencies
  -- only the first time NeoVim is opened, because that's when Packer gets installed
  if packerBootstrap then
    require('packer').sync()
  end
end)

-- small plugin pre-init goes here
require("indent_blankline").setup {
  char = "│",
  filetype_exclude = { "help", "alpha", "dashboard", "neo-tree", "Trouble", "lazy" },
  --show_current_context = true,
  --show_current_context_start = true,
}
require('mini.indentscope').setup({
  symbol = "│",
  options = { try_as_border = true },
})

-- plugin specific configs go here
require('plugin-config/nvim-cmp')
require('plugin-config/telescope')
require('plugin-config/nvim-treesitter')
require('plugin-config/lsp-trouble')
require('plugin-config/lspsaga')
require('plugin-config/galaxyline')
require('plugin-config/gitsigns')
require('plugin-config/indent-guide-lines')
require('plugin-config/dressing')
require('plugin-config/noice')
require('plugin-config/ministarter')

return packer
