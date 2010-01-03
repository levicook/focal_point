require File.expand_path(File.dirname(__FILE__)) + "/../lib/focal_point"


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

at_exit do
  FocalPoint.print_timers
end
