{ ... }:

{
  services.keyd = {
    enable = true;
    keyboards.default = {
      ids = [ "*" "-0b05:19b6:98a603e5" ];
      settings.main = {
        leftmeta = "overload(meta, macro(leftmeta+d))";
      };
    };
  };
}