# The virtual base class for properties, which are the self-contained building
# blocks for actually doing work on the system.

require 'puppet'
require 'puppet/parameter'

class Puppet::Property < Puppet::Parameter
  require 'puppet/property/ensure'

  # Because 'should' uses an array, we have a special method for handling
  # it.  We also want to keep copies of the original values, so that
  # they can be retrieved and compared later when merging.
  attr_reader :shouldorig

  attr_writer :noop

  class << self
    attr_accessor :unmanaged
    attr_reader :name

    # Return array matching info, defaulting to just matching
    # the first value.
    def array_matching
      @array_matching ||= :first
    end

    # Set whether properties should match all values or just the first one.
    def array_matching=(value)
      value = value.intern if value.is_a?(String)
      raise ArgumentError, "Supported values for Property#array_matching are 'first' and 'all'" unless [:first, :all].include?(value)
      @array_matching = value
    end
  end

  # Look up a value's name, so we can find options and such.
  def self.value_name(name)
    if value = value_collection.match?(name)
      value.name
    end
  end

  # Retrieve an option set when a value was defined.
  def self.value_option(name, option)
    if value = value_collection.value(name)
      value.send(option)
    end
  end

  # Define a new valid value for a property.  You must provide the value itself,
  # usually as a symbol, or a regex to match the value.
  #
  # The first argument to the method is either the value itself or a regex.
  # The second argument is an option hash; valid options are:
  # * <tt>:method</tt>: The name of the method to define.  Defaults to 'set_<value>'.
  # * <tt>:required_features</tt>: A list of features this value requires.
  # * <tt>:event</tt>: The event that should be returned when this value is set.
  # * <tt>:call</tt>: When to call any associated block.  The default value
  #   is `instead`, which means to call the value instead of calling the
  #   provider.  You can also specify `before` or `after`, which will
  #   call both the block and the provider, according to the order you specify
  #   (the `first` refers to when the block is called, not the provider).
  def self.newvalue(name, options = {}, &block)
    value = value_collection.newvalue(name, options, &block)

    define_method(value.method, &value.block) if value.method and value.block
    value
  end

  # Call the provider method.
  def call_provider(value)
      provider.send(self.class.name.to_s + "=", value)
  rescue NoMethodError
      self.fail "The #{provider.class.name} provider can not handle attribute #{self.class.name}"
  end

  # Call the dynamically-created method associated with our value, if
  # there is one.
  def call_valuemethod(name, value)
    if method = self.class.value_option(name, :method) and self.respond_to?(method)
      begin
        event = self.send(method)
      rescue Puppet::Error
        raise
      rescue => detail
        error = Puppet::ResourceError.new("Could not set '#{value}' on #{self.class.name}: #{detail}", @resource.line, @resource.file, detail)
        error.set_backtrace detail.backtrace
        Puppet.log_exception(detail, error.message)
        raise error
      end
    elsif block = self.class.value_option(name, :block)
      # FIXME It'd be better here to define a method, so that
      # the blocks could return values.
      self.instance_eval(&block)
    else
      devfail "Could not find method for value '#{name}'"
    end
  end

  # How should a property change be printed as a string?
  def change_to_s(current_value, newvalue)
    begin
      if current_value == :absent
        return "defined '#{name}' as #{self.class.format_value_for_display should_to_s(newvalue)}"
      elsif newvalue == :absent or newvalue == [:absent]
        return "undefined '#{name}' from #{self.class.format_value_for_display is_to_s(current_value)}"
      else
        return "#{name} changed #{self.class.format_value_for_display is_to_s(current_value)} to #{self.class.format_value_for_display should_to_s(newvalue)}"
      end
    rescue Puppet::Error, Puppet::DevError
      raise
    rescue => detail
      message = "Could not convert change '#{name}' to string: #{detail}"
      Puppet.log_exception(detail, message)
      raise Puppet::DevError, message
    end
  end

  # Figure out which event to return.
  def event_name
    value = self.should

    event_name = self.class.value_option(value, :event) and return event_name

    name == :ensure or return (name.to_s + "_changed").to_sym

    return (resource.type.to_s + case value
    when :present; "_created"
    when :absent; "_removed"
    else
      "_changed"
    end).to_sym
  end

  # Return a modified form of the resource event.
  def event
    resource.event :name => event_name, :desired_value => should, :property => self, :source_description => path
  end

  attr_reader :shadow

  # initialize our property
  def initialize(hash = {})
    super

    if ! self.metaparam? and klass = Puppet::Type.metaparamclass(self.class.name)
      setup_shadow(klass)
    end
  end

  # Determine whether the property is in-sync or not.  If @should is
  # not defined or is set to a non-true value, then we do not have
  # a valid value for it and thus consider the property to be in-sync
  # since we cannot fix it.  Otherwise, we expect our should value
  # to be an array, and if @is matches any of those values, then
  # we consider it to be in-sync.
  #
  # Don't override this method.
  def safe_insync?(is)
    # If there is no @should value, consider the property to be in sync.
    return true unless @should

    # Otherwise delegate to the (possibly derived) insync? method.
    insync?(is)
  end

  def self.method_added(sym)
    raise "Puppet::Property#safe_insync? shouldn't be overridden; please override insync? instead" if sym == :safe_insync?
  end

  # This method may be overridden by derived classes if necessary
  # to provide extra logic to determine whether the property is in
  # sync.  In most cases, however, only `property_matches?` needs to be
  # overridden to give the correct outcome - without reproducing all the array
  # matching logic, etc, found here.
  def insync?(is)
    self.devfail "#{self.class.name}'s should is not array" unless @should.is_a?(Array)

    # an empty array is analogous to no should values
    return true if @should.empty?

    # Look for a matching value, either for all the @should values, or any of
    # them, depending on the configuration of this property.
    if match_all? then
      # Emulate Array#== using our own comparison function.
      # A non-array was not equal to an array, which @should always is.
      return false unless is.is_a? Array

      # If they were different lengths, they are not equal.
      return false unless is.length == @should.length

      # Finally, are all the elements equal?  In order to preserve the
      # behaviour of previous 2.7.x releases, we need to impose some fun rules
      # on "equality" here.
      #
      # Specifically, we need to implement *this* comparison: the two arrays
      # are identical if the is values are == the should values, or if the is
      # values are == the should values, stringified.
      #
      # This does mean that property equality is not commutative, and will not
      # work unless the `is` value is carefully arranged to match the should.
      return (is == @should or is == @should.map(&:to_s))

      # When we stop being idiots about this, and actually have meaningful
      # semantics, this version is the thing we actually want to do.
      #
      # return is.zip(@should).all? {|a, b| property_matches?(a, b) }
    else
      return @should.any? {|want| property_matches?(is, want) }
    end
  end

  # Compare the current and desired value of a property in a property-specific
  # way.  Invoked by `insync?`; this should be overridden if your property
  # has a different comparison type but does not actually differentiate the
  # overall insync? logic.
  def property_matches?(current, desired)
    # This preserves the older Puppet behaviour of doing raw and string
    # equality comparisons for all equality.  I am not clear this is globally
    # desirable, but at least it is not a breaking change. --daniel 2011-11-11
    current == desired or current == desired.to_s
  end

  # because the @should and @is vars might be in weird formats,
  # we need to set up a mechanism for pretty printing of the values
  # default to just the values, but this way individual properties can
  # override these methods
  def is_to_s(currentvalue)
    currentvalue
  end

  # Send a log message.
  def log(msg)
    Puppet::Util::Log.create(
      :level   => resource[:loglevel],
      :message => msg,
      :source  => self
    )
  end

  # Should we match all values, or just the first?
  def match_all?
    self.class.array_matching == :all
  end

  # Execute our shadow's munge code, too, if we have one.
  def munge(value)
    self.shadow.munge(value) if self.shadow

    super
  end

  # each property class must define the name method, and property instances
  # do not change that name
  # this implicitly means that a given object can only have one property
  # instance of a given property class
  def name
    self.class.name
  end

  # for testing whether we should actually do anything
  def noop
    # This is only here to make testing easier.
    if @resource.respond_to?(:noop?)
      @resource.noop?
    else
      if defined?(@noop)
        @noop
      else
        Puppet[:noop]
      end
    end
  end

  # By default, call the method associated with the property name on our
  # provider.  In other words, if the property name is 'gid', we'll call
  # 'provider.gid' to retrieve the current value.
  def retrieve
    provider.send(self.class.name)
  end

  # Set our value, using the provider, an associated block, or both.
  def set(value)
    # Set a name for looking up associated options like the event.
    name = self.class.value_name(value)

    call = self.class.value_option(name, :call) || :none

    if call == :instead
      call_valuemethod(name, value)
    elsif call == :none
      # They haven't provided a block, and our parent does not have
      # a provider, so we have no idea how to handle this.
      self.fail "#{self.class.name} cannot handle values of type #{value.inspect}" unless @resource.provider
      call_provider(value)
    else
      # LAK:NOTE 20081031 This is a change in behaviour -- you could
      # previously specify :call => [;before|:after], which would call
      # the setter *in addition to* the block.  I'm convinced this
      # was never used, and it makes things unecessarily complicated.
      # If you want to specify a block and still call the setter, then
      # do so in the block.
      devfail "Cannot use obsolete :call value '#{call}' for property '#{self.class.name}'"
    end
  end

  # If there's a shadowing metaparam, instantiate it now.
  # This allows us to create a property or parameter with the
  # same name as a metaparameter, and the metaparam will only be
  # stored as a shadow.
  def setup_shadow(klass)
    @shadow = klass.new(:resource => self.resource)
  end

  # Only return the first value
  def should
    return nil unless defined?(@should)

    self.devfail "should for #{self.class.name} on #{resource.name} is not an array" unless @should.is_a?(Array)

    if match_all?
      return @should.collect { |val| self.unmunge(val) }
    else
      return self.unmunge(@should[0])
    end
  end

  # Set the should value.
  def should=(values)
    values = [values] unless values.is_a?(Array)

    @shouldorig = values

    values.each { |val| validate(val) }
    @should = values.collect { |val| self.munge(val) }
  end

  def should_to_s(newvalue)
    [newvalue].flatten.join(" ")
  end

  def sync
    devfail "Got a nil value for should" unless should
    set(should)
  end

  # Verify that the passed value is valid.
  # If the developer uses a 'validate' hook, this method will get overridden.
  def unsafe_validate(value)
    super
    validate_features_per_value(value)
  end

  # Make sure that we've got all of the required features for a given value.
  def validate_features_per_value(value)
    if features = self.class.value_option(self.class.value_name(value), :required_features)
      features = Array(features)
      needed_features = features.collect { |f| f.to_s }.join(", ")
      raise ArgumentError, "Provider must have features '#{needed_features}' to set '#{self.class.name}' to '#{value}'" unless provider.satisfies?(features)
    end
  end

  # Just return any should value we might have.
  def value
    self.should
  end

  # Match the Parameter interface, but we really just use 'should' internally.
  # Note that the should= method does all of the validation and such.
  def value=(value)
    self.should = value
  end
end
