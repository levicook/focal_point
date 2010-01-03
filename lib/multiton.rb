# = Multiton
#
# == Synopsis
#
# Multiton design pattern ensures only one object is allocated for a given state.
#
# The 'multiton' pattern is similar to a singleton, but instead of only one
# instance, there are several similar instances.  It is useful when you want to
# avoid constructing objects many times because of some huge expense (connecting
# to a database for example), require a set of similar but not identical
# objects, and cannot easily control how many times a contructor may be called.
#
#   class SomeMultitonClass
#     include Multiton
#     attr :arg
#     def initialize(arg)
#       @arg = arg
#     end
#   end
#
#   a = SomeMultitonClass.new(4)
#   b = SomeMultitonClass.new(4)   # a and b are same object
#   c = SomeMultitonClass.new(2)   # c is a different object
#
# == Previous Behavior
#
# In previous versions of Multiton the #new method was made
# private and #instance had to be used in its stay --just like Singleton.
# But this is less desirable for Multiton since Multitions can
# have multiple instances, not just one.
#
# So instead Multiton now defines #create as a private alias of
# the original #new method (just in case it is needed) and then
# defines #new to handle the multiton; #instance is provided
# as an alias for it.
#
#--
# So if you must have the old behavior, all you need do is re-alias
# #new to #create and privatize it.
#
#   class SomeMultitonClass
#     include Multiton
#     alias_method :new, :create
#     private :new
#     ...
#   end
#
# Then only #instance will be available for creating the Multiton.
#++
#
# == How It Works
#
# A pool of objects is searched for a previously cached object,
# if one is not found we construct one and cache it in the pool
# based on class and the args given to the contructor.
#
# A limitation of this approach is that it is impossible to
# detect if different blocks were given to a contructor (if it takes a
# block).  So it is the constructor arguments _only_ which determine
# the uniqueness of an object. To workaround this, define the _class_
# method ::multiton_id.
#
#   def Klass.multiton_id(*args, &block)
#     # ...
#   end
#
# Which should return a hash key used to identify the object being
# constructed as (not) unique.
#
# == Authors
#
# * Christoph Rippel
# * Thomas Sawyer
#
# = Copying
#
# Copyright (c) 2007 Christoph Rippel, Thomas Sawyer
#
# Ruby License
#
# This module is free software. You may use, modify, and/or redistribute this
# software under the same terms as Ruby.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE.

require 'thread'

# = Multiton
#
# Multiton design pattern ensures only one object is allocated for a given state.
#
# The 'multiton' pattern is similar to a singleton, but instead of only one
# instance, there are several similar instances.  It is useful when you want to
# avoid constructing objects many times because of some huge expense (connecting
# to a database for example), require a set of similar but not identical
# objects, and cannot easily control how many times a contructor may be called.
#
#   class SomeMultitonClass
#     include Multiton
#     attr :arg
#     def initialize(arg)
#       @arg = arg
#     end
#   end
#
#   a = SomeMultitonClass.new(4)
#   b = SomeMultitonClass.new(4)   # a and b are same object
#   c = SomeMultitonClass.new(2)   # c is a different object
#
# == How It Works
#
# A pool of objects is searched for a previously cached object,
# if one is not found we construct one and cache it in the pool
# based on class and the args given to the contructor.
#
# A limitation of this approach is that it is impossible to
# detect if different blocks were given to a contructor (if it takes a
# block).  So it is the constructor arguments _only_ which determine
# the uniqueness of an object. To workaround this, define the _class_
# method ::multiton_id.
#
#   def Klass.multiton_id(*args, &block)
#     # ...
#   end
#
# Which should return a hash key used to identify the object being
# constructed as (not) unique.

module Multiton

  #  disable build-in copying methods

  def clone
    raise TypeError, "can't clone Multiton #{self}"
    #self
  end

  def dup
    raise TypeError, "can't dup Multiton #{self}"
    #self
  end

  # default marshalling strategy

  protected

  def _dump(depth=-1)
    Marshal.dump(@multiton_initializer)
  end

  # Mutex to safely store multiton instances.

  class InstanceMutex < Hash  #:nodoc:
    def initialize
      @global = Mutex.new
    end

    def initialized(arg)
      store(arg, DummyMutex)
    end

    def (DummyMutex = Object.new).synchronize
      yield
    end

    def default(arg)
      @global.synchronize{ fetch(arg){ store(arg, Mutex.new) } }
    end
  end

  # Multiton can be included in another module, in which case that module effectively becomes
  # a multiton behavior distributor too. This is why we propogate #included to the base module.
  # by putting it in another module.
  #
  #--
  #    def append_features(mod)
  #      #  help out people counting on transitive mixins
  #      unless mod.instance_of?(Class)
  #        raise TypeError, "Inclusion of Multiton in module #{mod}"
  #      end
  #      super
  #    end
  #++

  module Inclusive
    private
    def included(base)
      class << base
        #alias_method(:new!, :new) unless method_defined?(:new!)
        # gracefully handle multiple inclusions of Multiton
        unless include?(Multiton::MetaMethods)
          alias_method :new!, :new
          private :allocate #, :new
          include Multiton::MetaMethods

          if method_defined?(:marshal_dump)
            undef_method :marshal_dump
            warn "warning: marshal_dump was undefined since it is incompatible with the Multiton pattern"
          end
        end
      end
    end
  end

  extend Inclusive

  #

  module MetaMethods

    include Inclusive

    def instance(*e, &b)
      arg = multiton_id(*e, &b)
      multiton_instance.fetch(arg) do
        multiton_mutex[arg].synchronize do
          multiton_instance.fetch(arg) do
            val = multiton_instance[arg] = new!(*e, &b) #new(*e, &b)
            val.instance_variable_set(:@multiton_initializer, e, &b)
            multiton_mutex.initialized(arg)
            val
          end
        end
      end
    end
    alias_method :new, :instance

    def initialized?(*e, &b)
      multiton_instance.key?(multiton_id(*e, &b))
    end

    protected

    def multiton_instance
      @multiton_instance ||= Hash.new
    end

    def multiton_mutex
      @multiton_mutex ||= InstanceMutex.new
    end

    def reinitialize
      multiton_instance.clear
      multiton_mutex.clear
    end

    def _load(str)
      instance(*Marshal.load(str))
    end

    private

    # Default method to to create a key to cache already constructed
    # instances. In the use case MultitonClass.new(e), MultiClass.new(f)
    # must be semantically equal if multiton_id(e).eql?(multiton_id(f))
    # evaluates to true.
    def multiton_id(*e, &b)
      e
    end

    def singleton_method_added(sym)
      super
      if (sym == :marshal_dump) & singleton_methods.include?('marshal_dump')
        raise TypeError, "Don't use marshal_dump - rely on _dump and _load instead"
      end
    end

  end

end
