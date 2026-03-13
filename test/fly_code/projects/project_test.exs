defmodule FlyCode.Projects.ProjectTest do
  use FlyCode.DataCase, async: true

  alias FlyCode.Projects.Project

  @valid_attrs %{name: "my-project", repo_url: "https://github.com/org/repo.git"}

  describe "changeset/2" do
    test "valid with name and repo_url" do
      changeset = Project.changeset(%Project{}, @valid_attrs)
      assert changeset.valid?
    end

    test "defaults branch to main" do
      changeset = Project.changeset(%Project{}, @valid_attrs)
      assert Ecto.Changeset.get_field(changeset, :default_branch) == "main"
    end

    test "allows overriding default_branch" do
      changeset = Project.changeset(%Project{}, Map.put(@valid_attrs, :default_branch, "develop"))
      assert Ecto.Changeset.get_field(changeset, :default_branch) == "develop"
    end

    test "requires name" do
      changeset = Project.changeset(%Project{}, Map.delete(@valid_attrs, :name))
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end

    test "requires repo_url" do
      changeset = Project.changeset(%Project{}, Map.delete(@valid_attrs, :repo_url))
      assert %{repo_url: ["can't be blank"]} = errors_on(changeset)
    end

    test "validates name length between 1 and 100" do
      changeset = Project.changeset(%Project{}, %{@valid_attrs | name: ""})
      assert %{name: [_]} = errors_on(changeset)

      long_name = String.duplicate("a", 101)
      changeset = Project.changeset(%Project{}, %{@valid_attrs | name: long_name})
      assert %{name: [_]} = errors_on(changeset)
    end

    test "enforces unique name constraint" do
      {:ok, _} = %Project{} |> Project.changeset(@valid_attrs) |> Repo.insert()

      {:error, changeset} = %Project{} |> Project.changeset(@valid_attrs) |> Repo.insert()
      assert %{name: ["has already been taken"]} = errors_on(changeset)
    end
  end
end
