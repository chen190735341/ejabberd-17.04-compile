%%%----------------------------------------------------------------------
%%% File    : ejabberd_sup.erl
%%% Author  : Alexey Shchepin <alexey@process-one.net>
%%% Purpose : Erlang/OTP supervisor
%%% Created : 31 Jan 2003 by Alexey Shchepin <alexey@process-one.net>
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

-module(ejabberd_sup).
-author('alexey@process-one.net').

-behaviour(supervisor).

-export([start_link/0, init/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
	%% hook系统
    Hooks =
	{ejabberd_hooks,
	 {ejabberd_hooks, start_link, []},
	 permanent,
	 brutal_kill,
	 worker,
	 [ejabberd_hooks]},
	%% 系统监控，监控堆使用情况
    SystemMonitor =
	{ejabberd_system_monitor,
	 {ejabberd_system_monitor, start_link, []},
	 permanent,
	 brutal_kill,
	 worker,
	 [ejabberd_system_monitor]},
	%% 服务器和服务器的通信
    S2S =
	{ejabberd_s2s,
	 {ejabberd_s2s, start_link, []},
	 permanent,
	 brutal_kill,
	 worker,
	 [ejabberd_s2s]},
	%% 验证码系统
    Captcha =
	{ejabberd_captcha,
	 {ejabberd_captcha, start_link, []},
	 permanent,
	 brutal_kill,
	 worker,
	 [ejabberd_captcha]},
	%% 监听启动进程监督进程
    Listener =
	{ejabberd_listener,
	 {ejabberd_listener, start_link, []},
	 permanent,
	 infinity,
	 supervisor,
	 [ejabberd_listener]},
	%% 其他服务器向本服务器发起的连接
    S2SInSupervisor =
	{ejabberd_s2s_in_sup,
	 {ejabberd_tmp_sup, start_link,
	  [ejabberd_s2s_in_sup, ejabberd_s2s_in]},
	 permanent,
	 infinity,
	 supervisor,
	 [ejabberd_tmp_sup]},
	%% 本服务器向其他服务器发起的连接
    S2SOutSupervisor =
	{ejabberd_s2s_out_sup,
	 {ejabberd_tmp_sup, start_link,
	  [ejabberd_s2s_out_sup, ejabberd_s2s_out]},
	 permanent,
	 infinity,
	 supervisor,
	 [ejabberd_tmp_sup]},
    ServiceSupervisor =
	{ejabberd_service_sup,
	 {ejabberd_tmp_sup, start_link,
	  [ejabberd_service_sup, ejabberd_service]},
	 permanent,
	 infinity,
	 supervisor,
	 [ejabberd_tmp_sup]},
	%% iq节handler处理模块
    IQSupervisor =
	{ejabberd_iq_sup,
	 {ejabberd_tmp_sup, start_link,
	  [ejabberd_iq_sup, gen_iq_handler]},
	 permanent,
	 infinity,
	 supervisor,
	 [ejabberd_tmp_sup]},
	%% 后台监督进程
    BackendSupervisor = {ejabberd_backend_sup,
			 {ejabberd_backend_sup, start_link, []},
			 permanent, infinity, supervisor,
			 [ejabberd_backend_sup]},
	%% 访问和规则相关处理
    ACL = {acl, {acl, start_link, []},
	   permanent, 5000, worker, [acl]},
	%% 流量控制
    Shaper = {shaper, {shaper, start_link, []},
	   permanent, 5000, worker, [shaper]},
	%% sql
    SQLSupervisor = {ejabberd_rdbms,
		     {ejabberd_rdbms, start_link, []},
		     permanent, infinity, supervisor, [ejabberd_rdbms]},
    RiakSupervisor = {ejabberd_riak_sup,
		     {ejabberd_riak_sup, start_link, []},
		      permanent, infinity, supervisor, [ejabberd_riak_sup]},
	%% redis数据库管理
    RedisSupervisor = {ejabberd_redis_sup,
		       {ejabberd_redis_sup, start_link, []},
		       permanent, infinity, supervisor, [ejabberd_redis_sup]},
	%% 路由管理中心
    Router = {ejabberd_router, {ejabberd_router, start_link, []},
	      permanent, 5000, worker, [ejabberd_router]},
	%% 群发路由管理中心
    RouterMulticast = {ejabberd_router_multicast,
		       {ejabberd_router_multicast, start_link, []},
		       permanent, 5000, worker, [ejabberd_router_multicast]},
	%%本域数据包路由处理和iq handler处理
    Local = {ejabberd_local, {ejabberd_local, start_link, []},
	     permanent, 5000, worker, [ejabberd_local]},
	%% ejabberd session manager 
    SM = {ejabberd_sm, {ejabberd_sm, start_link, []},
	  permanent, 5000, worker, [ejabberd_sm]},
	%% 模块启动
    GenModSupervisor = {ejabberd_gen_mod_sup, {gen_mod, start_link, []},
			permanent, infinity, supervisor, [gen_mod]},
    ExtMod = {ext_mod, {ext_mod, start_link, []},
	      permanent, 5000, worker, [ext_mod]},
	%%　登录模块
    Auth = {ejabberd_auth, {ejabberd_auth, start_link, []},
	    permanent, 5000, worker, [ejabberd_auth]},
    OAuth = {ejabberd_oauth, {ejabberd_oauth, start_link, []},
	     permanent, 5000, worker, [ejabberd_oauth]},
	%% 语言模块
    Translation = {translate, {translate, start_link, []},
		   permanent, 5000, worker, [translate]},
	%% ejabberd访问权限控制模块
    AccessPerms = {ejabberd_access_permissions,
		   {ejabberd_access_permissions, start_link, []},
		   permanent, 5000, worker, [ejabberd_access_permissions]},
	%% 脚本命令处理
    Ctl = {ejabberd_ctl, {ejabberd_ctl, start_link, []},
	   permanent, 5000, worker, [ejabberd_ctl]},
	%% 命令管理模块
    Commands = {ejabberd_commands, {ejabberd_commands, start_link, []},
		permanent, 5000, worker, [ejabberd_commands]},
	%% amdin命令处理
    Admin = {ejabberd_admin, {ejabberd_admin, start_link, []},
	     permanent, 5000, worker, [ejabberd_admin]},
	%% cyrsasl 模块
    CyrSASL = {cyrsasl, {cyrsasl, start_link, []},
	       permanent, 5000, worker, [cyrsasl]},
    {ok, {{one_for_one, 10, 1},
	  [Hooks,
	   CyrSASL,
	   Translation,
	   AccessPerms,
	   Ctl,
	   Commands,
	   Admin,
	   Listener,
	   SystemMonitor,
	   S2S,
	   Captcha,
	   S2SInSupervisor,
	   S2SOutSupervisor,
	   ServiceSupervisor,
	   IQSupervisor,
	   ACL,
	   Shaper,
	   BackendSupervisor,
	   SQLSupervisor,
	   RiakSupervisor,
	   RedisSupervisor,
	   Router,
	   RouterMulticast,
	   Local,
	   SM,
	   ExtMod,
	   GenModSupervisor,
	   Auth,
	   OAuth]}}.
