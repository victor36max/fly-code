defmodule FlyCode.Projects.EnvVarTest do
  use FlyCode.DataCase, async: true

  alias FlyCode.Projects.EnvVar

  @valid_attrs %{key: "MY_VAR", value: "secret", scope: :global}

  describe "changeset/2" do
    test "valid with key, value, and scope" do
      changeset = EnvVar.changeset(%EnvVar{}, @valid_attrs)
      assert changeset.valid?
    end

    test "requires key" do
      changeset = EnvVar.changeset(%EnvVar{}, Map.delete(@valid_attrs, :key))
      assert %{key: ["can't be blank"]} = errors_on(changeset)
    end

    test "requires value" do
      changeset = EnvVar.changeset(%EnvVar{}, Map.delete(@valid_attrs, :value))
      assert %{value: ["can't be blank"]} = errors_on(changeset)
    end

    test "requires scope" do
      changeset = EnvVar.changeset(%EnvVar{}, Map.delete(@valid_attrs, :scope))
      assert %{scope: ["can't be blank"]} = errors_on(changeset)
    end

    test "validates key format - allows valid env var names" do
      for key <- ~w(MY_VAR _PRIVATE var123 A) do
        changeset = EnvVar.changeset(%EnvVar{}, %{@valid_attrs | key: key})
        assert changeset.valid?, "Expected #{key} to be valid"
      end
    end

    test "validates key format - rejects invalid env var names" do
      for key <- ["1STARTS_WITH_NUMBER", "has spaces", "has-dash", ""] do
        changeset = EnvVar.changeset(%EnvVar{}, %{@valid_attrs | key: key})
        assert %{key: [_]} = errors_on(changeset), "Expected #{key} to be invalid"
      end
    end

    test "enforces unique constraint on key + scope + project_id" do
      project = FlyCode.Fixtures.project_fixture()
      attrs = Map.put(@valid_attrs, :project_id, project.id) |> Map.put(:scope, :project)

      {:ok, _} = %EnvVar{} |> EnvVar.changeset(attrs) |> Repo.insert()
      {:error, changeset} = %EnvVar{} |> EnvVar.changeset(attrs) |> Repo.insert()
      assert %{key: ["has already been taken"]} = errors_on(changeset)
    end
  end
end
