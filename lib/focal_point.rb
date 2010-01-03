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

  class << self

    # FocalPoint.watch("ClassName#instance_method")
    # FocalPoint.watch("ClassName.class_method")
    def watch(*targets)
      targets.each { |t| FocalPoint.new(t) }
    end

    def report(io=$stdout)
      timers = []
      ObjectSpace.each_object(FocalPoint) { |fp| timers << fp.timer }
      timers.compact.sort_by(&:sum).each do |timer|
        io.puts '-'*80
        timer.to_hash.each { |k,v| io.puts "#{k}: #{v}" }
        io.puts
      end
    end

  end
end
