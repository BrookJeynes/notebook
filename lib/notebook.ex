defmodule CmdArguments do
  def get_arguments() do
    optimus = Optimus.new!(
      name: "notebook",
      description: "A simple way to view notes",
      version: "0.1.0",
      author: "Brook Jeynes",
      about: "A TUI application to allow quick and easy access to notes from a notebook.",
      allow_unknown_args: false,
      parse_double_dash: true,
      options: [
        directory: [
          value_name: "DIRECTORY",
          short: "-d",
          long: "--directory",
          help: "The directory where your notes are stored. i.e. ~/notes",
          # Maybe validate the input ensuring it's a valid path
          # parser: fn(s) ->
          # end,
          required: true
        ],
      ]
      ) 

    args = Optimus.parse!(optimus, System.argv())

    case args do
      %{options: %{directory: x}} -> %{:directory => x}
      # display help when not given any args
      %{options: %{}} -> Optimus.parse!(optimus, ["--help"])
    end
  end
end

# Module to handle IO operations in regards to notes
defmodule Notes do
  def read_files(directory) do
    case File.ls(directory) do
      {:ok, files} -> files
      {:error, _} -> []
    end
  end
end

defmodule Notebook do
  @behaviour Ratatouille.App

  import Ratatouille.View
  import Ratatouille.Constants, only: [key: 1]

  alias Ratatouille.Runtime.Command

  @args CmdArguments.get_arguments()
  @tab key(:tab)
  @panes [
    :content,
    :module
  ]

  def init(_context) do
    directory = Map.get(@args, :directory)    
    files = Notes.read_files(directory)
            |> Enum.filter(fn (x) -> String.at(x, 0) != "." end)

    model = %{
      content: "",
      content_cursor: 0,
      module_cursor: 0,
      pane: :module,
      modules: files,
      directory: directory
    }

    {model, update_cmd(model)}
  end

  def update(
        %{
          content_cursor: content_cursor,
          module_cursor: module_cursor,
          pane: pane,
          modules: modules
        } = model,
        msg
      ) do
    case msg do
      {:event, %{ch: ?k}} ->
        case pane do
          :content ->
            %{model | content_cursor: max(content_cursor - 1, 0)}

          :module ->
            new_model = %{model | module_cursor: max(module_cursor - 1, 0)}
            {new_model, update_cmd(new_model)}
        end

      {:event, %{ch: ?j}} ->
        case pane do
          :content ->
            %{model | content_cursor: content_cursor + 1}

          :module ->
            new_model = %{
              model
              | module_cursor:
                  if module_cursor + 1 < length(modules) do
                    module_cursor + 1
                  else
                    module_cursor
                  end
            }

            {new_model, update_cmd(new_model)}
        end

      {:event, %{key: @tab}} ->
        case pane do
          :content ->
            %{model | pane: :module, content_cursor: 0}

          :module ->
            %{model | pane: :content, content_cursor: 0}
        end

      {:content_updated, content} ->
        %{model | content: content}

      _ ->
        model
    end
  end

  def render(model) do
    selected = Enum.at(model.modules, model.module_cursor)

    controls =
      bar do
        label(content: "q: Quit application")
      end

    view(bottom_bar: controls) do
      row do
        column(size: 3) do
          panel(title: "Notes", height: :fill) do
            viewport(offset_y: model.module_cursor) do
              for {module, idx} <- Enum.with_index(model.modules) do
                if idx == model.module_cursor do
                  label(content: "> " <> inspect(module), attributes: [:bold])
                else
                  label(content: inspect(module))
                end
              end
            end
          end
        end

        column(size: 9) do
          panel(title: inspect(selected), height: :fill) do
            viewport(offset_y: model.content_cursor) do
              label(content: model.content, wrap: true)
            end
          end
        end
      end
    end
  end

  defp update_cmd(model) do
    Command.new(fn -> fetch_content(model) end, :content_updated)
  end

  defp fetch_content(%{module_cursor: cursor, modules: modules, directory: directory}) do
    selected = Enum.at(modules, cursor)

    case File.read("#{directory}/#{selected}") do
      {:ok, content} ->
        content
      {:error, err} ->
        case err do
          :eisdir -> "(Error reading content for #{selected} - the named file is a directory)"
          :eacces -> "(Error reading content for #{selected} - missing permission for reading the file, or for searching one of the parent directories)"
          _ -> 
            "(No documentation for #{selected})"
        end
    end
  end
end

Ratatouille.run(Notebook)
