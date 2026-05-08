{pkgs, ...}: {
  fonts = {
    enableDefaultPackages = true;
    fontconfig.enable = true;

    packages = with pkgs; [
      cascadia-code
      jetbrains-mono
      open-dyslexic
      source-serif
      source-sans
      noto-fonts
      noto-fonts-color-emoji
      noto-fonts-cjk-sans
      adwaita-fonts
    ];
  };
}
