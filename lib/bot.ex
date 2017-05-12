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

defmodule Player, do: defstruct [:room, :items]

defmodule Room, do: defstruct [:text, :doors, :name]

defmodule Rooms do
  @rooms [
    %Room{name: "room1", text: "you are in room 1", doors: ["room2", "room3"]},
    %Room{name: "room2", text: "you are in room 2", doors: ["room1"]},
    %Room{name: "room3", text: "you are in room 3", doors: ["room1"]},
  ]

  def rooms, do: @rooms

  def room(name) do
    @rooms |> Enum.find(fn(room) -> room.name == name end)
  end
end

defmodule Game do
  use GenServer

  def start_link(user_id) do
    name = via_tuple(user_id)
    GenServer.start_link(__MODULE__, %{player: %Player{room: "room1", items: []}}, name: name)
  end

  defp via_tuple(user_id) do
    {:via, Registry, {:games_registry, user_id}}
  end

  def next_message(pid, message) do
    GenServer.call(pid, {:next_message, message})
  end

  def process_message("h", state), do: process_message("help", state)
  def process_message("help", state) do
    {"Possible command are: 'go to', 'open'", state}
  end

  def process_message("open " <> room, state), do: process_message("go to " <> room, state)
  def process_message("go to " <> room, state), do: goto_room(Rooms.room(room), state)

  def goto_room(nil, _), do: {"Unknown room", %{}}
  def goto_room(next_room, state) do
    current_room = Rooms.room(state.player.room)
    if(current_room.doors |> Enum.member?(next_room.name)) do
      {next_room.text, %{player: %Player{state.player | room: next_room.name}}}
    else
      {"You can't get to there from here", %{}}
    end
  end

  def process_message(message, player) do
    {"ENGLISH MOTHERFUCKER, DO YOU SPEAK IT??", %{}}
  end

  def handle_call({:next_message, message}, _from, state) do
    IO.inspect state
    {message, new_state} = process_message(message.text, state) |> IO.inspect

    {:reply, message, state |> Map.merge(new_state)}
  end
end
