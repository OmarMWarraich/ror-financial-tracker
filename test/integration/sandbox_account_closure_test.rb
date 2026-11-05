require "test_helper"

class SandboxAccountClosureTest < ActionDispatch::IntegrationTest
  test "append-only sandbox account deletion is explicitly blocked rather than claiming success" do
    user = users(:one)
    sign_in user
    SandboxAccount.stub(:exists?, true) do
      assert_no_difference "User.count" do
        delete user_registration_path
      end
    end
    assert_redirected_to edit_user_registration_path
    assert_includes flash[:alert], "append-only synthetic sandbox ledger"
    assert User.exists?(user.id)
  end

  test "ordinary account deletion without a sandbox preserves Devise behavior" do
    user = User.create!(email: "ordinary-closure@example.invalid", password: "example-only-password")
    sign_in user
    assert_difference "User.count", -1 do
      delete user_registration_path
    end
    assert_redirected_to root_path
  end
end
