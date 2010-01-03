require 'rubygems'
require 'hitimes'
require 'pp'

require File.expand_path(File.dirname(__FILE__)) + "/multiton"

class FocalPoint
  include Multiton

  attr_accessor :timer

  def self.[] target
    new(target)
  end

  def initialize(target)
    @target = String(target)
    @timer = Hitimes::TimedMetric.new(@target)

    if @target =~ /^([^#.]+)(#|\.)(.*)$/
      @method, @scope = case $2
                        when '#' ## we're instrumenting an instance method
                          [$3, eval($1)]
                        when '.' ## we're instrumenting a module method
                          [$3, (class << eval($1); self; end)]
                        end
    else
      $stdout.puts "FocalPoint::Error: Not sure how to instrument #{@target}"
    end
    @scope.module_eval(source)
  end

  def source 
    <<-CODE
      alias :real_#{@method} :#{@method}
      def #{@method}(*args)
        FocalPoint[#{@target.inspect}].timer.measure do
          real_#{@method}(*args)
        end
      end
    CODE
  end


  def self.print_timers
    timers = []
    ObjectSpace.each_object(FocalPoint) { |fp| timers << fp.timer }
    timers.compact.sort_by(&:sum).each do |timer|
      puts '-'*80
      pp timer.to_hash
      puts
    end
  end

end

# call-seq:
#
#  focal_point("ClassName#instance_method", ...)
#  focal_point("ClassName.class_method", ...)
#
#
def focal_point(*targets)
  targets.each { |t| FocalPoint[t] }
end
alias :focal_points :focal_point


=begin

at_exit do
  FocalPoint.print_timers
end

if $0 == __FILE__
  module Quux
    class Foo
      def self.bar
        5.times { sleep(1) }
      end
      def bar
        5.times { sleep(1) }
      end
    end
  end
  focal_points('Quux::Foo.bar', 'Quux::Foo#bar')
  Quux::Foo.bar
  Quux::Foo.new.bar
end

=end
