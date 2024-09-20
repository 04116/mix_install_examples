# WTF: eventsource_ex block infinity if server don't send back



# # Usage: elixir eventsource_ex_chatgpt.exs openai-api-key "prompt"
# #
# # func: make a call to openai, then print out response
# #
#
# Mix.install([
#   {:eventsource_ex, "~> 2.0"},
#   {:httpoison, "~> 1.5"},
#   {:jason, "~> 1.4"}
# ])
#
# defmodule ChatGPTStreamer do
#   use GenServer
#
#   def start_link(state) do
#     GenServer.start_link(__MODULE__, state)
#   end
#
#   # this func return the init state of model
#   # the init state gather by make a httpReq to openai, so it is the resp from it
#   # the arg state hold param that parent process give
#   def init(state) do
#     {:ok, request_completion(state[:api_key], state[:messages], state[:parent_pid])}
#   end
#
#    # some process must send messages to the ChatGPTStreamer process
#   # then this func will be call if inp match
#   #
#   # the form: { req, from, cur_state }
#   def handle_info(
#         %EventsourceEx.Message{
#           data: "[DONE]",
#           event: "message"
#         },
#         parent_pid
#       ) do
#     IO.puts("")
#     send(parent_pid, :done)
#     {:stop, :normal, nil}
#   end
#
#   def handle_info(
#         %EventsourceEx.Message{
#           data: jason_payload,
#           event: "message"
#         },
#         state
#       ) do
#     jason_payload |> Jason.decode!() |> extract_text() |> IO.write()
#
#     {:noreply, state}
#   end
#
#   def extract_text(%{"choices" => choices}) do
#     for %{"delta" => %{"content" => content}} <- choices, into: "", do: content
#   end
#
#   def extract_text(_) do
#     ""
#   end
#
#   @chat_completion_url "https://api.openai.com/v1/chat/completions"
#   @model "gpt-3.5-turbo"
#
#   defp request_completion(api_key, messages, parent_pid) do
#     body = %{
#       model: @model,
#       messages: messages,
#       stream: true
#     }
#
#     headers = [
#       {"Authorization", "Bearer #{api_key}"},
#       {"Content-Type", "application/json"}
#     ]
#
#     IO.puts("hello world")
#     options = [method: :post, body: Jason.encode!(body), headers: headers, stream_to: self()]
#
#     # Start the event source to handle streaming responses
#     case EventsourceEx.new(@chat_completion_url, options) do
#       {:ok, _pid} ->
#         IO.puts("Event source created successfully.")
#         %{parent_pid: parent_pid}
#
#       {:error, reason} ->
#         IO.puts("Failed to create event source: #{inspect(reason)}")
#         {:stop, {:error, reason}, nil}
#     end
#
#     #
#     # # phuclm: call this func will make the new process that is event pusher
#     # # data from api call response
#     # {:ok, _pid} = EventsourceEx.new(@chat_completion_url, options)
#     # IO.puts("parent pid from arg #{inspect(parent_pid)}")
#     # IO.puts("current GenServer pid #{inspect(self())}")
#     # IO.puts("created eventsource_ex #{inspect(_pid)}")
#     # just need to keep the parent_id to notify when we done
#     parent_pid
#   end
# end
#
# Logger.configure(level: :info)
#
# [api_key, prompt] = System.argv()
#
# # start the stream here
# {:ok, _pid} =
#   ChatGPTStreamer.start_link(
#     api_key: api_key,
#     messages: [%{role: "user", content: prompt}],
#     parent_pid: self()
#   )
#
# IO.puts("at root, self() and returned: #{inspect(self())}, #{inspect(_pid)}")
#
# # wait until recv the :done message
# # :done - the atomic alias, just a way to optimize memory consume
# receive do
#   :done -> true
# end
#
#
#
# Usage: elixir eventsource_ex_chatgpt.exs openai-api-key "prompt"

Mix.install([
  {:eventsource_ex, "~> 2.0"},
  {:httpoison, "~> 1.5"},
  {:jason, "~> 1.4"}
])

defmodule ChatGPTStreamer do
  use GenServer
  require Logger

  def start_link(args) do
    GenServer.start_link(__MODULE__, args)
  end

  def init(args) do
    state = %{
      api_key: args[:api_key],
      messages: args[:messages],
      parent_pid: args[:parent_pid]
    }
    # phuclm: send async message to process
    GenServer.cast(self(), :start_streaming)
    {:ok, state}
  end

  def handle_cast(:start_streaming, state) do
    request_completion(state)
    {:noreply, state}
  end

  def handle_info(
      %EventsourceEx.Message{
        data: error_message,
        event: "error"
      },
      state
    ) do
    IO.puts("Error: #{error_message}")
    send(state[:parent_pid], {:error, error_message})
    {:stop, :error, state}
  end

  def handle_info(%EventsourceEx.Message{data: "[DONE]", event: "message"}, state) do
    IO.puts("")
    send(state.parent_pid, :done)
    {:stop, :normal, state}
  end

  def handle_info(%EventsourceEx.Message{data: jason_payload, event: "message"}, state) do
    jason_payload |> Jason.decode!() |> extract_text() |> IO.write()
    {:noreply, state}
  end

  defp extract_text(%{"choices" => choices}) do
    for %{"delta" => %{"content" => content}} <- choices, into: "", do: content
  end

  defp extract_text(_), do: ""

  @chat_completion_url "https://api.openai.com/v1/chat/completions"
  @model "gpt-3.5-turbo"

  defp request_completion(state) do
    body = %{
      model: @model,
      messages: state.messages,
      stream: true
    }

    headers = [
      {"Authorization", "Bearer #{state.api_key}"},
      {"Content-Type", "application/json"}
    ]

    IO.puts("requester pid, which must be the recv of EventsourceEx #{inspect(self())}")
    options = [
      method: :post,
      body: Jason.encode!(body),
      headers: headers,
      stream_to: self(),
      follow_redirect: true,
      ssl: false,
    ]
    Logger.debug(fn -> "options #{inspect(options)}" end)
    {:ok, pid} = EventsourceEx.new(@chat_completion_url, options)
    Logger.debug("eventsource_ex pid #{inspect(pid)}")
  end
end

Logger.configure(level: :trace)

[api_key, prompt] = System.argv()

{:ok, _pid} = ChatGPTStreamer.start_link(
  api_key: api_key,
  messages: [%{role: "user", content: prompt}],
  parent_pid: self()
)

receive do
  :done -> :ok
  {:error, error_message} -> IO.puts("Received error: #{error_message}")
end
