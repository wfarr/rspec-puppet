module RSpec::Puppet
  module Support

    @@cache = {}

    def catalogue(type)
      vardir = setup_puppet

      code = pre_cond + test_manifest(type)
      node_name = nodename(type)

      catalogue = build_catalog(node_name, facts_for_node(node_name), code)
      FileUtils.rm_rf(vardir) if File.directory?(vardir)
      catalogue
    end

    def test_manifest(type)
      klass_name = self.class.top_level_description.downcase

      if type == :class
        if !self.respond_to?(:params) || params == {}
          "include #{klass_name}"
        else
          "class { '#{klass_name}': #{param_str} }"
        end
      elsif type == :define
        if self.respond_to? :params
          "#{klass_name} { '#{title}': #{param_str} }"
        end
      elsif type == :host
        ""
      end
    end

    def nodename(type)
      if [:class, :define, :function].include? type
        self.respond_to?(:node) ? node : Puppet[:certname]
      else
        self.class.top_level_description.downcase
      end
    end


    def pre_cond
      if self.respond_to?(:pre_condition) && !pre_condition.nil?
        if pre_condition.is_a? Array
          pre_condition.join("\n")
        else
          pre_condition
        end
      else
        ''
      end
    end

    def facts_for_node(node)
      base_facts(node).tap do |h|
        h.merge(munge_facts(default_facts)) if default_facts
        h.merge(munge_facts(facts)) if self.respond_to? :facts
      end
    end

    def default_facts
      @default_facts ||= RSpec.configuration.default_facts
    end

    def base_facts(node)
      {
        'hostname' => node.split('.').first,
        'fqdn'     => node,
        'domain'   => node.split('.').last,
      }
    end

    def param_str
      params.keys.map do |r|
        param_val = escape_special_chars(params[r].inspect)
        "#{r.to_s} => #{param_val}"
      end.join(', ')
    end

    def setup_puppet
      vardir = Dir.mktmpdir
      Puppet[:vardir] = vardir

      [
        [:modulepath, :module_path],
        [:manifestdir, :manifest_dir],
        [:manifest, :manifest],
        [:templatedir, :template_dir],
        [:config, :config],
        [:confdir, :confdir],
      ].each do |a, b|
        if self.respond_to? b
          Puppet[a] = self.send(b)
        else
          Puppet[a] = RSpec.configuration.send(b)
        end
      end

      if Puppet[:hiera_config] == File.expand_path('/dev/null')
        Puppet[:hiera_config] = File.join(vardir, 'hiera.yaml')
      end

      Puppet[:libdir] = Dir["#{Puppet[:modulepath]}/*/lib"].entries.join(File::PATH_SEPARATOR)
      vardir
    end

    def build_catalog_without_cache(nodename, facts_val, code)
      Puppet[:code] = code

      stub_facts! facts_val

      node_obj = Puppet::Node.new(nodename)

      node_obj.merge(facts_val)

      # trying to be compatible with 2.7 as well as 2.6
      if Puppet::Resource::Catalog.respond_to? :find
        Puppet::Resource::Catalog.find(node_obj.name, :use_node => node_obj)
      else
        Puppet::Resource::Catalog.indirection.find(node_obj.name, :use_node => node_obj)
      end
    end

    def stub_facts!(facts)
      facts.each { |k, v| Facter.add(k) { setcode { v } } }
    end

    def build_catalog(*args)
      @@cache[args] ||= self.build_catalog_without_cache(*args)
    end

    def munge_facts(facts)
      output = {}
      facts.keys.each { |key| output[key.to_s] = facts[key] }
      output
    end

    def escape_special_chars(string)
      string.gsub!(/\$/, "\\$")
      string
    end

    def scope(compiler, node_name)
      if Puppet.version =~ /^2\.[67]/
        # loadall should only be necessary prior to 3.x
        # Please note, loadall needs to happen first when creating a scope, otherwise
        # you might receive undefined method `function_*' errors
        Puppet::Parser::Functions.autoloader.loadall
        scope = Puppet::Parser::Scope.new(:compiler => compiler)
      else
        scope = Puppet::Parser::Scope.new(compiler)
      end

      scope.source = Puppet::Resource::Type.new(:node, node_name)
      scope.parent = compiler.topscope
      scope
    end

    def build_node(name, opts = {})
      node_environment = Puppet::Node::Environment.new('test')
      opts.merge!({:environment => node_environment})
      Puppet::Node.new(name, opts)
    end
  end
end
