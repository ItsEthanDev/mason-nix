_: let
  timezone = "America/Phoenix";
  identifier = "en_US.UTF-8";
in {
  time.timeZone = timezone;
  i18n.defaultLocale = identifier;
  i18n.extraLocaleSettings = {
    LC_ADDRESS = identifier;
    LC_IDENTIFICATION = identifier;
    LC_MEASUREMENT = identifier;
    LC_MONETARY = identifier;
    LC_NAME = identifier;
    LC_NUMERIC = identifier;
    LC_PAPER = identifier;
    LC_TELEPHONE = identifier;
    LC_TIME = identifier;
  };
}
