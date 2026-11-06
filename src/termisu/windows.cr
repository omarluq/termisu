{% if flag?(:win32) %}
  require "./system/console"
  require "./system/console/input"
  require "./system/console/output"
  require "./system/console/readiness_lease"
{% end %}
