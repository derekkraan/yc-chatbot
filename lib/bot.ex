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

defmodule Enemy, do: defstruct [:name, :damage, :health]

defmodule Player do
  defstruct [:room, :items, :health]

  def has_item?(_, _), do: false
end

defmodule Room do
  defstruct [:text, :doors, :name, :items, :enemy]

  def door(room, door_name), do: room.doors |> Enum.find(fn(door) -> door.name == door_name end)
end

defmodule Door do
  defstruct [:name, :room, :needs_key]

  def can_enter?(door, player), do: !door.needs_key || player |> Player.has_item?(door.needs_key)
end

defmodule Item, do: defstruct [:name, :text, :damage]

defmodule Rooms do
  @enemies [
    %Enemy{
      name: "Ruben",
      damage: 20,
      health: 100
    }
  ]

  @rooms [
    %Room{
      name: "the parking lot",
      text: "You are on the parking lot of YoungCapital, the flags are moving in the wind. Looking at the building you see that there are two entrances, an `orange door` on the left with a big YoungCapital sign above it, and `a glass` door on right. Which door do you pick?",
      doors: [
        %Door{name: "A", room: "room2", needs_key: "key1"},
        %Door{name: "B", room: "room3"}
      ],
      items: [%Item{name: "key1", text: "Keyfob", damage: 1}],
      enemy: ""
    },
    %Room{
      name: "room2",
      text: "you are in room 2",
      doors: [%Door{name: "Y", room: "the parking lot"}],
      items: [],
      enemy: "",
    },
    %Room{
      name: "room3",
      text: "you are in room 3",
      doors: [%Door{name: "X", room: "the parking lot"}],
      items: [],
      enemy: ""
    },
    %Room{
      name: "room4",
      text: "you are in room 4",
      doors: [],
      items: [],
      enemy: "Ruben"
    },
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
    GenServer.start_link(__MODULE__, %{player: %Player{room: "the parking lot", items: [], health: 100}}, name: name)
  end

  defp via_tuple(user_id) do
    {:via, Registry, {:games_registry, user_id}}
  end

  def next_message(pid, message) do
    GenServer.call(pid, {:next_message, message})
  end

  def current_room(state), do: Rooms.room(state.player.room)

  def process_message("h", state), do: process_message("help", state)
  def process_message("help", state) do
    {"Possible command are: 'go to', 'open', 'where am i'", %{}}
  end

  def process_message("where am i", state) do
    {current_room(state).text, %{}}
  end

  def process_message("open " <> room, state), do: process_message("go to " <> room, state)
  def process_message("go to " <> door, state) do
    door = current_room(state) |> Room.door(door)
    if(door) do
      if(door |> Door.can_enter?(state.player)) do
        goto_room(Rooms.room(door.room), state)
      else
        {"This door needs #{door.needs_key} to open!", %{}}
      end
    else
      {"You can't get to there from here", %{}}
    end
  end

  def goto_room(nil, _), do: {"Unknown room", %{}}
  def goto_room(next_room, state) do
    {next_room.text, %{player: %Player{state.player | room: next_room.name}}}
  end

  def process_message(message, state) do
    {Rooms.room(state.player.room).text, %{}}
  end

  def handle_call({:next_message, message}, _from, state) do
    IO.inspect message
    IO.inspect state
    {message, new_state} = process_message(message.text, state) |> IO.inspect

    {:reply, message, state |> Map.merge(new_state)}
  end
end
