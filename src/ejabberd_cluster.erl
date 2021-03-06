%%%----------------------------------------------------------------------
%%% File    : ejabberd_cluster.erl
%%% Author  : Christophe Romain <christophe.romain@process-one.net>
%%% Purpose : Ejabberd clustering management
%%% Created : 7 Oct 2015 by Christophe Romain <christophe.romain@process-one.net>
%%%
%%%
%%% ejabberd, Copyright (C) 2002-2017   ProcessOne
%%%
%%% This program is free software; you can redistribute it and/or
%%% modify it under the terms of the GNU General Public License as
%%% published by the Free Software Foundation; either version 2 of the
%%% License, or (at your option) any later version.
%%%
%%% This program is distributed in the hope that it will be useful,
%%% but WITHOUT ANY WARRANTY; without even the implied warranty of
%%% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
%%% General Public License for more details.
%%%
%%% You should have received a copy of the GNU General Public License along
%%% with this program; if not, write to the Free Software Foundation, Inc.,
%%% 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
%%%
%%%----------------------------------------------------------------------

-module(ejabberd_cluster).

%% API
-export([get_nodes/0, call/4, multicall/3, multicall/4]).
-export([join/1, leave/1, get_known_nodes/0]).
-export([node_id/0, get_node_by_id/1]).

-include("ejabberd.hrl").
-include("logger.hrl").

-spec get_nodes() -> [node()].

get_nodes() ->
    mnesia:system_info(running_db_nodes).

-spec get_known_nodes() -> [node()].

get_known_nodes() ->
    lists:usort(mnesia:system_info(db_nodes)
		++ mnesia:system_info(extra_db_nodes)).

-spec call(node(), module(), atom(), [any()]) -> any().

call(Node, Module, Function, Args) ->
    rpc:call(Node, Module, Function, Args, 5000).

-spec multicall(module(), atom(), [any()]) -> {list(), [node()]}.

multicall(Module, Function, Args) ->
    multicall(get_nodes(), Module, Function, Args).

-spec multicall([node()], module(), atom(), list()) -> {list(), [node()]}.

multicall(Nodes, Module, Function, Args) ->
    rpc:multicall(Nodes, Module, Function, Args, 5000).


-spec join(node()) -> ok | {error, any()}.
%% 加入集群
join(Node) ->
    case {node(), net_adm:ping(Node)} of
        {Node, _} ->
            {error, {not_master, Node}};
        {_, pong} ->
            application:stop(ejabberd),
            application:stop(mnesia),
            mnesia:delete_schema([node()]),
            application:start(mnesia),
            mnesia:change_config(extra_db_nodes, [Node]),
            mnesia:change_table_copy_type(schema, node(), disc_copies),
            spawn(fun()  ->
                lists:foreach(fun(Table) ->
                            Type = call(Node, mnesia, table_info, [Table, storage_type]),
                            mnesia:add_table_copy(Table, node(), Type)
                    end, mnesia:system_info(tables)--[schema])
                end),
            application:start(ejabberd);
        _ ->
            {error, {no_ping, Node}}
    end.

-spec leave(node()) -> ok | {error, any()}.

%% 从集群中删除节点Node
leave(Node) ->
    case {node(), net_adm:ping(Node)} of
        {Node, _} ->
			%% 被删除的节点是当前节点
            Cluster = get_nodes()--[Node],
            leave(Cluster, Node);
        {_, pong} ->
			%% 被删除的是远程节点
            rpc:call(Node, ?MODULE, leave, [Node], 10000);
        {_, pang} ->
            case mnesia:del_table_copy(schema, Node) of
                {atomic, ok} -> ok;
                {aborted, Reason} -> {error, Reason}
            end
    end.
leave([], Node) ->
    {error, {no_cluster, Node}};
leave([Master|_], Node) ->
	%% 停掉应用
    application:stop(ejabberd),
    application:stop(mnesia),
	%%删除离开集群节点的schema备份
    call(Master, mnesia, del_table_copy, [schema, Node]),
	%% 删除离开集群节点的数据库
    spawn(fun() ->
                mnesia:delete_schema([node()]),
                erlang:halt(0)
        end),
    ok.

-spec node_id() -> binary().
node_id() ->
    integer_to_binary(erlang:phash2(node())).

-spec get_node_by_id(binary()) -> node().
get_node_by_id(Hash) ->
    try binary_to_integer(Hash) of
	I -> match_node_id(I)
    catch _:_ ->
	    node()
    end.

%%%===================================================================
%%% Internal functions
%%%===================================================================
-spec match_node_id(integer()) -> node().
match_node_id(I) ->
    match_node_id(I, get_nodes()).

-spec match_node_id(integer(), [node()]) -> node().
match_node_id(I, [Node|Nodes]) ->
    case erlang:phash2(Node) of
	I -> Node;
	_ -> match_node_id(I, Nodes)
    end;
match_node_id(_I, []) ->
    node().
