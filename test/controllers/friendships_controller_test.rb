require "test_helper"

class FriendshipsControllerTest < ActionDispatch::IntegrationTest
  test "signed out users cannot follow or unfollow" do
    assert_no_difference "Friendship.count" do
      post friendships_path, params: { friend: users(:three).id }
      assert_redirected_to new_user_session_path
      delete friendship_path(users(:two))
      assert_redirected_to new_user_session_path
    end
  end

  test "following uses the signed in owner rather than submitted user id" do
    sign_in users(:one)
    assert_difference "users(:one).friendships.count", 1 do
      assert_no_difference "users(:two).friendships.count" do
        post friendships_path, params: { friend: users(:three).id, user_id: users(:two).id }
      end
    end
    assert_redirected_to my_friends_path
    assert users(:one).friends.exists?(users(:three).id)
  end

  test "unfollowing removes only the signed in user's relationship" do
    sign_in users(:one)
    assert_difference "Friendship.count", -1 do
      delete friendship_path(users(:two)), params: { user_id: users(:two).id }
    end
    assert_response :no_content
    assert_not users(:one).friends.exists?(users(:two).id)
    assert Friendship.exists?(friendships(:two).id)
  end
end
