{% if helpers.exists('OPNsense.terminal.general.enabled') and OPNsense.terminal.general.enabled == '0' %}
terminal_service_enable="NO"
{% else %}
terminal_service_enable="YES"
{% endif %}
terminal_service_default_shell="{{ OPNsense.terminal.general.default_shell|default('auto') }}"
