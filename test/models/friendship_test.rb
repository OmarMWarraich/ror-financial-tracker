require "test_helper"

class FriendshipTest < ActiveSupport::TestCase
  test "friendship requires an owner and a friend" do
    friendship = Friendship.new
    assert_not friendship.valid?
    assert_includes friendship.errors[:user], "must exist"
    assert_includes friendship.errors[:friend], "must exist"
  end

  test "friend association points to a different user record" do
    assert_equal users(:one), friendships(:one).user
    assert_equal users(:two), friendships(:one).friend
    assert_equal [users(:two)], users(:one).friends.to_a
  end
end
