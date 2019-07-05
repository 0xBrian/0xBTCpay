require "yaml"
module Config
  def self.load_file(fn)
    raise "ERROR: config file missing! expected #{fn}" unless File.exist?(fn)
    symbolize(YAML.load_file(fn))
  end
  def self.symbolize(h)
    h.collect { |k,v| [k.to_sym, v.is_a?(Hash) ? symbolize(v) : v] }.to_h
  end
end
