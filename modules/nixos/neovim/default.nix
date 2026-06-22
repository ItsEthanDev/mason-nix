{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.programs.neovim;
in {
  config = lib.mkIf cfg.enable {
    programs.neovim.configure = {
      packages.gruvbox = {
        start = with pkgs.vimPlugins; [gruvbox-nvim];
      };

      customLuaRC = ''
        vim.o.background = "dark"
        require("gruvbox").setup()
        vim.cmd("colorscheme gruvbox")
      '';
    };
  };
}
