%Name: Natthew Angelakos, Elliot Niemann
%Pledge: I pledge my honor that I have abided by the Stevens Honor System.
-module(server).

-export([start_server/0]).

-include_lib("./defs.hrl").

-spec start_server() -> _.
-spec loop(_State) -> _.
-spec do_join(_ChatName, _ClientPID, _Ref, _State) -> _.
-spec do_leave(_ChatName, _ClientPID, _Ref, _State) -> _.
-spec do_new_nick(_State, _Ref, _ClientPID, _NewNick) -> _.
-spec do_client_quit(_State, _Ref, _ClientPID) -> _NewState.

start_server() ->
    catch(unregister(server)),
    register(server, self()),
    case whereis(testsuite) of
	undefined -> ok;
	TestSuitePID -> TestSuitePID!{server_up, self()}
    end,
    loop(
      #serv_st{
	 nicks = maps:new(), %% nickname map. client_pid => "nickname"
	 registrations = maps:new(), %% registration map. "chat_name" => [client_pids]
	 chatrooms = maps:new() %% chatroom map. "chat_name" => chat_pid
	}
     ).

loop(State) ->
    receive 
	%% initial connection
	{ClientPID, connect, ClientNick} ->
	    NewState =
		#serv_st{
		   nicks = maps:put(ClientPID, ClientNick, State#serv_st.nicks),
		   registrations = State#serv_st.registrations,
		   chatrooms = State#serv_st.chatrooms
		  },
	    loop(NewState);
	%% client requests to join a chat
	{ClientPID, Ref, join, ChatName} ->
	    NewState = do_join(ChatName, ClientPID, Ref, State),
	    loop(NewState);
	%% client requests to join a chat
	{ClientPID, Ref, leave, ChatName} ->
	    NewState = do_leave(ChatName, ClientPID, Ref, State),
	    loop(NewState);
	%% client requests to register a new nickname
	{ClientPID, Ref, nick, NewNick} ->
	    NewState = do_new_nick(State, Ref, ClientPID, NewNick),
	    loop(NewState);
	%% client requests to quit
	{ClientPID, Ref, quit} ->
	    NewState = do_client_quit(State, Ref, ClientPID),
	    loop(NewState);
	{TEST_PID, get_state} ->
	    TEST_PID!{get_state, State},
	    loop(State)
    end.

%% executes join protocol from server perspective
do_join(ChatName, ClientPID, Ref, State) ->
	case maps:is_key(ChatName, State#serv_st.chatrooms) of
		true ->
			ChatroomPID = maps:get(ChatName, State#serv_st.chatrooms),
			Chatrooms = State#serv_st.chatrooms,
            Registrations = State#serv_st.registrations;
		false ->
			ChatroomPID = spawn(chatroom, start_chatroom, [ChatName]),
			Chatrooms = maps:put(ChatName,ChatroomPID,State#serv_st.chatrooms),
        	Registrations = maps:put(ChatName,[],State#serv_st.registrations)
	end,
	ClientNick = maps:get(ClientPID, State#serv_st.nicks),
	ChatroomPID!{self(), Ref, register, ClientPID, ClientNick},
	NewRegistrations = maps:update_with(ChatName, fun(Clients) -> [ClientPID|Clients] end, Registrations),
	NewState = State#serv_st{
        nicks = State#serv_st.nicks,
        registrations = NewRegistrations,
        chatrooms = Chatrooms
        },
	NewState.

%% executes leave protocol from server perspective
do_leave(ChatName, ClientPID, Ref, State) ->
	ChatroomPID = maps:get(ChatName, State#serv_st.chatrooms),
	Registrations = maps:get(ChatName, State#serv_st.registrations),
	NewRegistrations = lists:delete(ClientPID, Registrations),
	NewFullReg = maps:put(ChatName, NewRegistrations, State#serv_st.registrations),
	NewState = State#serv_st{registrations = NewFullReg},
	ChatroomPID!{self(), Ref, unregister, ClientPID},
	ClientPID!{self(), Ref, ack_leave},
	NewState.
    %io:format("server:do_leave(...): IMPLEMENT ME~n"),
    %State.

%% executes new nickname protocol from server perspective
do_new_nick(State, Ref, ClientPID, NewNick) ->
	case lists:keyfind(NewNick, 2, maps:to_list(State#serv_st.nicks)) of
		{_, _} ->
			ClientPID!{self(), Ref, err_nick_used},
			State;
		false ->
			NewNicks = maps:update(ClientPID, NewNick, State#serv_st.nicks),
			NewState = State#serv_st{nicks = NewNicks},
			Registrations = State#serv_st.registrations,
			Chats = maps:fold(fun(ChatName, Pids, Acc) ->
				case lists:member(ClientPID, Pids) of
					true  -> [ChatName | Acc];
					false -> Acc
				end
			end, [], Registrations),
			lists:foreach(fun(ChatName) ->
				ChatroomPID = maps:get(ChatName, State#serv_st.chatrooms),
				ChatroomPID!{self(), Ref, update_nick, ClientPID, NewNick} 
			end, Chats),
			ClientPID!{self(), Ref, ok_nick},
			NewState
	end.
    %io:format("server:do_new_nick(...): IMPLEMENT ME~n"),
    %State.
%% executes client quit protocol from server perspective
do_client_quit(State, Ref, ClientPID) ->
	NewNicks = maps:remove(ClientPID, State#serv_st.nicks),
	Registrations = State#serv_st.registrations,
	Chats = maps:fold(fun(ChatName, Pids, Acc) ->
		case lists:member(ClientPID, Pids) of
			true  -> [ChatName | Acc];
			false -> Acc
		end
	end, [], Registrations),
	NewRegistrations = maps:map(fun (_, V) ->
    lists:filter(fun(E) -> E /= ClientPID end, V) end, Registrations),
	lists:foreach(fun(ChatName) ->
		ChatroomPID = maps:get(ChatName, State#serv_st.chatrooms),
		ChatroomPID!{self(), Ref, unregister, ClientPID}
	end, Chats),
	ClientPID!{self(), Ref, ack_quit},
	NewState = State#serv_st{nicks = NewNicks, registrations=NewRegistrations},
	%NewState = State#serv_st{nicks = NewNicks},
	NewState.
    %io:format("server:do_client_quit(...): IMPLEMENT ME~n"),
    %State.
