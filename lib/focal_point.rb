require 'rubygems'
require 'hitimes'

require File.expand_path(File.dirname(__FILE__)) + "/multiton"

class FocalPoint
  include Multiton

  attr_accessor :timer

  def initialize(target)
    @target = String(target)
    @timer = Hitimes::TimedMetric.new(@target)

    if @target =~ /^([^#.]+)(#|\.)(.*)$/
      @method_name = $3
      @scope = case $2
               when '#' ## we're instrumenting an instance method
                 eval($1)
               when '.' ## we're instrumenting a module method
                 (class << eval($1); self; end)
                end
    else
      $stdout.puts "FocalPoint::Error: Not sure how to instrument #{@target}"
    end

    # make timer and unbound available to the lambda 
    timer = @timer
    unbound = @scope.instance_method(@method_name)
    @scope.send(:undef_method , @method_name)
    @scope.send(:define_method, @method_name) do |*args, &block|
      lambda {
        bound = unbound.bind(self)
        timer.measure { bound.call(*args, &block) }
      }.call
    end
  end

  def self.print_timers
    timers = []
    ObjectSpace.each_object(FocalPoint) { |fp| timers << fp.timer }
    timers.compact.sort_by(&:sum).each do |timer|
      puts '-'*80
      timer.to_hash.each { |k,v| puts "#{k}: #{v}" }
      puts
    end
  end

end

# call-seq:
#
#  focal_point("ClassName#instance_method", ...)
#  focal_point("ClassName.class_method", ...)
#
def focal_point(*targets)
  targets.each { |t| FocalPoint.new(t) }
end
alias :focal_points :focal_point


at_exit do
  FocalPoint.print_timers
end

if $0 == __FILE__
  module Quux
    class Foo
      attr_accessor :bin
      def self.bar
        5.times { sleep(1) }
        return :bar
      end
      def bar(&block)
        return block.call
      end
    end
  end
  focal_point('Quux::Foo.bar')
  focal_point('Quux::Foo.bar')
  focal_point('Quux::Foo#bar')
  focal_points('Quux::Foo#bin', 'Quux::Foo#bin=')

  fail unless Quux::Foo.bar == :bar

  fail unless Quux::Foo.new.bar do
    5.times { sleep(1) }
    :bar
  end == :bar

  5.times do 
    foo = Quux::Foo.new
    r = rand(1000)
    foo.bin = r
    fail unless foo.bin == r
  end
end
