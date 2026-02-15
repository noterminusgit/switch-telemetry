defmodule SwitchTelemetry.Accounts.UserNotifierTest do
  use ExUnit.Case, async: true

  alias SwitchTelemetry.Accounts.UserNotifier

  @test_user %{email: "test@example.com"}
  @test_url "https://switch-telemetry.local/confirm/abc123"

  describe "deliver_reset_password_instructions/2" do
    test "returns {:ok, %Swoosh.Email{}} with correct fields" do
      assert {:ok, %Swoosh.Email{} = email} =
               UserNotifier.deliver_reset_password_instructions(@test_user, @test_url)

      assert email.to == [{"", "test@example.com"}]
      assert email.from == {"Switch Telemetry", "noreply@switch-telemetry.local"}
      assert email.subject == "Reset password instructions"
      assert email.text_body =~ "test@example.com"
      assert email.text_body =~ @test_url
      assert email.text_body =~ "reset your password"
    end
  end

  describe "deliver_confirmation_instructions/2" do
    test "returns {:ok, %Swoosh.Email{}} with correct fields" do
      assert {:ok, %Swoosh.Email{} = email} =
               UserNotifier.deliver_confirmation_instructions(@test_user, @test_url)

      assert email.to == [{"", "test@example.com"}]
      assert email.from == {"Switch Telemetry", "noreply@switch-telemetry.local"}
      assert email.subject == "Confirmation instructions"
      assert email.text_body =~ "test@example.com"
      assert email.text_body =~ @test_url
      assert email.text_body =~ "confirm your account"
    end
  end

  describe "deliver_magic_link/2" do
    test "returns {:ok, %Swoosh.Email{}} with correct fields" do
      magic_url = "https://switch-telemetry.local/magic/token123"

      assert {:ok, %Swoosh.Email{} = email} =
               UserNotifier.deliver_magic_link(@test_user, magic_url)

      assert email.to == [{"", "test@example.com"}]
      assert email.from == {"Switch Telemetry", "noreply@switch-telemetry.local"}
      assert email.subject == "Sign in to Switch Telemetry"
      assert email.text_body =~ "test@example.com"
      assert email.text_body =~ magic_url
      assert email.text_body =~ "valid for 24 hours"
      assert email.text_body =~ "can only be used once"
    end
  end

  describe "deliver_generated_password/2" do
    test "returns {:ok, %Swoosh.Email{}} with correct fields" do
      password = "temp_pass_abc123"

      assert {:ok, %Swoosh.Email{} = email} =
               UserNotifier.deliver_generated_password(@test_user, password)

      assert email.to == [{"", "test@example.com"}]
      assert email.from == {"Switch Telemetry", "noreply@switch-telemetry.local"}
      assert email.subject == "Your Switch Telemetry account"
      assert email.text_body =~ "test@example.com"
      assert email.text_body =~ password
      assert email.text_body =~ "temporary password"
    end
  end
end
