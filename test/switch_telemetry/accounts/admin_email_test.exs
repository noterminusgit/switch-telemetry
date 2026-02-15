defmodule SwitchTelemetry.Accounts.AdminEmailTest do
  use SwitchTelemetry.DataCase, async: true

  alias SwitchTelemetry.Accounts.AdminEmail

  @valid_attrs %{email: "admin@example.com"}

  describe "changeset/2 with valid email" do
    test "produces a valid changeset" do
      changeset = AdminEmail.changeset(%AdminEmail{}, @valid_attrs)
      assert changeset.valid?
    end

    test "accepts various valid email formats" do
      valid_emails = [
        "user@domain.com",
        "user+tag@domain.co.uk",
        "user.name@sub.domain.org",
        "a@b.c"
      ]

      for email <- valid_emails do
        changeset = AdminEmail.changeset(%AdminEmail{}, %{email: email})
        assert changeset.valid?, "expected #{email} to be valid"
      end
    end
  end

  describe "changeset/2 with blank email" do
    test "requires email to be present" do
      changeset = AdminEmail.changeset(%AdminEmail{}, %{})
      assert %{email: ["can't be blank"]} = errors_on(changeset)
    end

    test "rejects nil email" do
      changeset = AdminEmail.changeset(%AdminEmail{}, %{email: nil})
      assert %{email: ["can't be blank"]} = errors_on(changeset)
    end

    test "rejects empty string email" do
      changeset = AdminEmail.changeset(%AdminEmail{}, %{email: ""})
      assert %{email: ["can't be blank"]} = errors_on(changeset)
    end
  end

  describe "changeset/2 with invalid email format" do
    test "rejects email without @ sign" do
      changeset = AdminEmail.changeset(%AdminEmail{}, %{email: "notanemail"})
      assert %{email: ["must have the @ sign and no spaces"]} = errors_on(changeset)
    end

    test "rejects email with spaces" do
      changeset = AdminEmail.changeset(%AdminEmail{}, %{email: "user @example.com"})
      assert %{email: ["must have the @ sign and no spaces"]} = errors_on(changeset)
    end

    test "rejects email with spaces after @" do
      changeset = AdminEmail.changeset(%AdminEmail{}, %{email: "user@ example.com"})
      assert %{email: ["must have the @ sign and no spaces"]} = errors_on(changeset)
    end
  end

  describe "changeset/2 with email length" do
    test "rejects email longer than 160 characters" do
      long_email = String.duplicate("a", 150) <> "@example.com"
      changeset = AdminEmail.changeset(%AdminEmail{}, %{email: long_email})
      assert %{email: ["should be at most 160 character(s)"]} = errors_on(changeset)
    end

    test "accepts email at exactly 160 characters" do
      # 160 chars total: 148 + @ + 11 (example.com) = 160
      email = String.duplicate("a", 148) <> "@example.com"
      assert String.length(email) == 160
      changeset = AdminEmail.changeset(%AdminEmail{}, %{email: email})
      assert changeset.valid?
    end
  end

  describe "changeset/2 uniqueness" do
    test "enforces unique email constraint" do
      # Insert the first admin email
      {:ok, _admin_email} =
        %AdminEmail{}
        |> AdminEmail.changeset(@valid_attrs)
        |> Repo.insert()

      # Attempt to insert a duplicate
      {:error, changeset} =
        %AdminEmail{}
        |> AdminEmail.changeset(@valid_attrs)
        |> Repo.insert()

      assert %{email: ["has already been taken"]} = errors_on(changeset)
    end

    test "unsafe_validate_unique catches duplicates before insert" do
      {:ok, _admin_email} =
        %AdminEmail{}
        |> AdminEmail.changeset(@valid_attrs)
        |> Repo.insert()

      changeset = AdminEmail.changeset(%AdminEmail{}, @valid_attrs)
      assert %{email: ["has already been taken"]} = errors_on(changeset)
    end
  end
end
