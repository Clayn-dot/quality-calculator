-- quality-calculator: player settings.
data:extend({
  {
    type = "string-setting",
    name = "qcalc-recycler-mode",
    setting_type = "runtime-per-user",
    default_value = "by-quality",
    allowed_values = {"by-quality", "any"},
    order = "a",
  },
  {
    type = "bool-setting",
    name = "qcalc-skip-blocked",
    setting_type = "runtime-per-user",
    default_value = true,
    order = "c",
  },
  {
    type = "bool-setting",
    name = "qcalc-limit-by-supply",
    setting_type = "runtime-per-user",
    default_value = true,
    order = "d",
  },
  {
    type = "string-setting",
    name = "qcalc-keep-from",
    setting_type = "runtime-per-user",
    default_value = "highest",
    allowed_values = {"highest", "epic", "rare", "uncommon"},
    order = "b",
  },
})
