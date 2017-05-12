defmodule BotApp do
  use Application

  def start(_type, _args) do
    import Supervisor.Spec

    slack_token = System.get_env("SLACK_TOKEN")

    # Define workers and child supervisors to be supervised
    children = [
      worker(Slack.Bot, [Bot, [], slack_token]),
      supervisor(Registry, [:unique, :games_registry])
    ]

    # See http://elixir-lang.org/docs/stable/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Eslixir.Supervisor]
    Supervisor.start_link(children, opts)
  end
end

defmodule Bot do
  use Slack

  def handle_connect(slack, state) do
    IO.puts "Connected as #{slack.me.name}"
    {:ok, state}
  end

  def handle_event(message = %{type: "message"}, slack, state) do
    with {_, {_, pid}} <- Game.start_link(message.user) do
      pid |> Game.next_message(message)
      |> send_message(message.channel, slack)
    end
    {:ok, state}
  end

  def handle_event(_, _, state), do: {:ok, state}

  def handle_info({:message, text, channel}, slack, state) do
    IO.puts "Sending your message, captain!"

    send_message(text, channel, slack)

    {:ok, state}
  end

  def handle_info(_, _, state), do: {:ok, state}
end

defmodule Games do
end

defmodule Game do
  use GenServer

  def start_link(user_id) do
    name = via_tuple(user_id)
    GenServer.start_link(__MODULE__, [user_id], name: name)
  end

  defp via_tuple(user_id) do
    {:via, Registry, {:games_registry, user_id}}
  end

  def next_message(pid, message) do
    GenServer.call(pid, {:next_message, message})
  end

  def handle_call({:next_message, message}, _from, state) do
    {:reply, "MESSAGE FROM GAME", state}
  end
end
