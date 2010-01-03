require 'teststrap'

context "focal_point" do

  setup do
    false
  end

  asserts "i'm a failure :(" do
    topic
    fail
  end

end
