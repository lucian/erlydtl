%%%-------------------------------------------------------------------
%%% File:      erlydtl_server.erl
%%% @author    Roberto Saccon <rsaccon@gmail.com> [http://rsaccon.com]
%%% @copyright 2007 Roberto Saccon
%%% @doc  
%%% Server for compiling ErlyDTL templeates
%%% @end  
%%%
%%% The MIT License
%%%
%%% Copyright (c) 2007 Roberto Saccon
%%%
%%% Permission is hereby granted, free of charge, to any person obtaining a copy
%%% of this software and associated documentation files (the "Software"), to deal
%%% in the Software without restriction, including without limitation the rights
%%% to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
%%% copies of the Software, and to permit persons to whom the Software is
%%% furnished to do so, subject to the following conditions:
%%%
%%% The above copyright notice and this permission notice shall be included in
%%% all copies or substantial portions of the Software.
%%%
%%% THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
%%% IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
%%% FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
%%% AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
%%% LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
%%% OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
%%% THE SOFTWARE.
%%%
%%% @since 2007-11-17 by Roberto Saccon
%%%-------------------------------------------------------------------
-module(erlydtl_server).
-author('rsaccon@gmail.com').

-behaviour(gen_server).
	
%% API
-export([start_link/0, compile/1, compile/3, compile/4]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-record(state, {}).


%%====================================================================
%% API
%%====================================================================
%%--------------------------------------------------------------------
%% @spec start_link() -> {ok,Pid} | ignore | {error,Error}
%% @doc Starts the server
%% @end 
%%--------------------------------------------------------------------
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).
    

%%--------------------------------------------------------------------
%% @spec (File:string()) -> 
%%     {Ok::atom, Ast::tuple() | {Error::atom(), Msg:string()}
%% @doc compiles a template to a beam file
%% @end 
%%--------------------------------------------------------------------
compile(File) ->
    compile(File, todo, todo).
        
%%--------------------------------------------------------------------
%% @spec (File:string(), ModuleName:string(), DocRoot:string()) -> 
%%     {Ok::atom, Ast::tuple() | {Error::atom(), Msg:string()}
%% @doc compiles a template to a beam file
%% @end 
%%--------------------------------------------------------------------
compile(File, ModuleName, DocRoot) ->
    compile(File, ModuleName, DocRoot, "render").
    

%%--------------------------------------------------------------------
%% @spec (File:string(), ModuleName:string(), DocRoot:string(), FunctionName:atom()) -> 
%%     {Ok::atom, Ast::tuple() | {Error::atom(), Msg:string()}
%% @doc compiles a template to a beam file
%% @end 
%%--------------------------------------------------------------------
compile(File, ModuleName, DocRoot, FunctionName) ->   
    gen_server:call(?MODULE, {compile, File, ModuleName, DocRoot, FunctionName}).
        

	

%%====================================================================
%% gen_server callbacks
%%====================================================================

%%--------------------------------------------------------------------
%% @spec init(Args) -> {ok, State} |
%%                         {ok, State, Timeout} |
%%                         ignore               |
%%                         {stop, Reason}
%% @doc Initiates the server
%% @end 
%%--------------------------------------------------------------------
init([]) ->
    {ok, #state{}}.

%%--------------------------------------------------------------------
%% @spec 
%% handle_call(Request, From, State) -> {reply, Reply, State} |
%%                                      {reply, Reply, State, Timeout} |
%%                                      {noreply, State} |
%%                                      {noreply, State, Timeout} |
%%                                      {stop, Reason, Reply, State} |
%%                                      {stop, Reason, State}
%% @doc Handling call messages
%% @end 
%%--------------------------------------------------------------------
handle_call({compile, File, ModuleName, DocRoot, FunctionName}, _From, State) ->
    Reply = case parse(File) of
        {ok, Ast} ->
		    RelDir = rel_dir(filename:dirname(File), DocRoot),
		    Ext = filename:extension(File),
            compile_reload_ast(Ast, ModuleName, FunctionName, RelDir, Ext);
        {error, Msg} = Err ->
            io:format("TRACE ~p:~p ~p~n",[?MODULE, ?LINE, File ++ " Parser failure:"]),
            io:format("TRACE ~p:~p ~p~n",[?MODULE, ?LINE, Msg]),
            Err
    end,
    {reply, Reply, State};

handle_call(_Request, _From, State) ->
    Reply = ok,
    {reply, Reply, State}.

%%--------------------------------------------------------------------
%% @spec handle_cast(Msg, State) -> {noreply, State} |
%%                                      {noreply, State, Timeout} |
%%                                      {stop, Reason, State}
%% @doc Handling cast messages
%% @end 
%%--------------------------------------------------------------------
handle_cast(_Msg, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% @spec handle_info(Info, State) -> {noreply, State} |
%%                                       {noreply, State, Timeout} |
%%                                       {stop, Reason, State}
%% @doc Handling all non call/cast messages
%% @end 
%%--------------------------------------------------------------------
handle_info(_Info, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% @spec terminate(Reason, State) -> void()
%% @doc This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any necessary
%% cleaning up. When it returns, the gen_server terminates with Reason.
%% The return value is ignored.
%% @end 
%%--------------------------------------------------------------------
terminate(_Reason, _State) ->
    ok.

%%--------------------------------------------------------------------
%% @spec code_change(OldVsn, State, Extra) -> {ok, NewState}
%% @doc Convert process state when code is changed
%% @end 
%%--------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.	


%%====================================================================
%% Internal functions
%%====================================================================


parse(File) ->
	case file:read_file(File) of
		{ok, B} ->
	        case erlydtl_scanner:scan(binary_to_list(B)) of
	            {ok, Tokens} ->
	                erlydtl_parser:parse(Tokens);
	            Err ->
	                io:format("TRACE ~p:~p ~p~n",[?MODULE, ?LINE, File ++ " Scanner failure:"]),
	                io:format("TRACE ~p:~p ~p~n",[?MODULE, ?LINE, Err]),
	                Err
	        end;
	    Err ->
	        io:format("TRACE ~p:~p ~p: ~p~n",[?MODULE, ?LINE, "File read error with:", File]),
	        Err   
	end.
	

compile_reload_ast([H | T], ModuleName, FunctionName, RelDir, Ext) ->
    {List, Args} = case walk_ast(H, T, [], [], RelDir, Ext) of
	    {regular, List0, Args0} ->
		    {[parse_transform(X) ||  X <- List0], Args0};
		{inherited, List0, Arg0} ->
			{List0, Arg0}
	end,	           
    Args2 = lists:reverse([{var, 1, Val} || {Val, _} <- Args]),  
    Cons = list_fold(lists:reverse(List)),                           
    Ast2 = {function, 1, list_to_atom(FunctionName), length(Args2),
        [{clause, 1, Args2, [], [Cons]}]},
    Ac = erlydtl_tools:create_module(Ast2 , ModuleName),   
    case compile:forms(Ac) of
        {ok, Module, Bin} ->
            case erlydtl_tools:reload(Module, Bin) of
                ok ->
                    erlydtl_tools:write_beam(Module, Bin, "ebin");
                _ -> 
                    {error, "reload failed"}
            end;            
        _ ->
           {error, "compilation failed"}
    end.                      


walk_ast(nil, [{extends, _Line, Name}], Out, Args, RelDir, Ext) -> 
    case parse(filename:join([RelDir, Name])) of
        {ok, ParentAst} ->
		    [H|T]=ParentAst,
			{_, List, Args1} = walk_ast(H, T, [], [], RelDir, Ext),			 
			{List3, Args3} = lists:foldl(fun(X, {List2, Args2}) -> 
                {List4, Args4} = parse_transform(X, Out, Args2, Ext),            
                {[List4 | List2], Args4}
            end, {[], Args1}, List),		   
		    {inherited, lists:reverse(lists:flatten([List3])), lists:flatten(Args3)};
	    {error, Msg} ->
	         io:format("TRACE ~p:~p ~p~n",[?MODULE, ?LINE, Msg]),
	         io:format("TRACE ~p:~p Parent Parser failure: ~p~n",[?MODULE, ?LINE, Name]),
		     {regular, Out, Args}			
    end;
	
walk_ast(nil, [{var, Line, Val}], Out, Args, _, _) ->
    case lists:keysearch(Val, 2, Args) of
        false ->
            Key = list_to_atom(lists:concat(["A", length(Args) + 1])),
            {regular, [{var, Line, Key} | Out], [{Key, Val} | Args]}; 
        {value, {Key, _}} ->   
            {regular, [{var, Line, Key} | Out], Args}
    end;
    
walk_ast(nil, [{tag, _Line, [TagName | TagArgs]}], Out, Args, _, Ext) ->
    Out2 = load_tag(TagName, TagArgs, Out, default, Ext),    
    {regular, Out2, Args};
    
walk_ast(nil, [{for, _Line, Var, List, Content}], Out, Args, _, Ext) ->
io:format("TRACE ~p:~p Content-nil: ~p~n",[?MODULE, ?LINE, Content]),
     Out2 = Out,
     {regular, Out2, Args};    
    
walk_ast(nil, [Token], Out, Args, _, _) ->
    {regular, [Token | Out], Args}; 
	
walk_ast([H | T], [{var, Line, Val}], Out, Args, DocRoot, Ext) ->
    case lists:keysearch(Val, 2, Args) of
        false ->           
            Key = list_to_atom(lists:concat(["A", length(Args) + 1])),
            walk_ast(H, T, [{var, Line, Key} | Out], [{Key, Val} | Args], DocRoot, Ext);
        {value, {Key, _}} ->  
            walk_ast(H, T, [{var, Line, Key} | Out], Args, DocRoot, Ext)
	end;	 
	
walk_ast([H | T], [{tag, _Line, [TagName | TagArgs]}], Out, Args, DocRoot, Ext) ->
    Out2 = load_tag(TagName, TagArgs, Out, default, Ext),
    walk_ast(H, T, Out2, Args, DocRoot, Ext);
    
walk_ast([H | T], [{for, _Line, Var, List, [nil | TFor]}], Out, Args, DocRoot, Ext) ->
io:format("TRACE ~p:~p Content-not-nil: ~p~n",[?MODULE, ?LINE, T]),  %%
    % just subst. var
    Out2 = Out,
    walk_ast(H, T, Out2, Args, DocRoot, Ext);     

walk_ast([H | T], [{for, _Line, Var, List, [HFor | TFor]}], Out, Args, DocRoot, Ext) -> 
    %% List2 = lists:foldl(fun(X, Acc) -> 
    %%         {_, List1, _Args1} = walk_ast(HFor, TFor, [], [], undefined, Ext),
    %%         [parse_transform(Y, X, Var)  || Y <- List1]                
    %%     end,
    %%     [],
    %%     List),
    %% io:format("TRACE ~p:~p Content-not-nil-out1: ~p~n",[?MODULE, ?LINE, List2]),
    %% io:format("TRACE ~p:~p Content-not-nil-out2: ~p~n",[?MODULE, ?LINE, lists:flatten(List2)]),
    io:format("TRACE ~p:~p Content-not-nil-out1: ~p~n",[?MODULE, ?LINE, Var]),
    io:format("TRACE ~p:~p Content-not-nil-out1: ~p~n",[?MODULE, ?LINE, List]),
    io:format("TRACE ~p:~p Content-not-nil-out1: ~p~n",[?MODULE, ?LINE, [HFor | TFor]]),
    Out2 = Out,
    walk_ast(H, T, Out2, Args, DocRoot, Ext);	
	
walk_ast([H | T], [Token], Out, Args, DocRoot, Ext) ->      
    walk_ast(H, T, [Token | Out], Args, DocRoot, Ext).


parse_transform({block, _Line, Name, [nil, Val]}, List, Args, Ext) ->
	case lists:keysearch(Name, 3, List) of
		false -> 
			{Val, Args};
		{value, {_, _, _, [H | T]}} ->  
		    {_, List2, Args2} = walk_ast(H, T, [], Args, undefined, Ext),
		    {lists:reverse(List2), Args2} 
 	end;
parse_transform(Other, _What, Args, _) ->	
	{Other, Args}.

    
parse_transform({var, Line, Var}, Var1, Var) when is_atom(Var1) ->
    {var, Line, Var1}.
    
            
parse_transform({var, Line, Var}, Args) ->
    {value, {_, Val}} = lists:keysearch(Var, 1, Args),
    {string, Line, Val};            
parse_transform(Other, _) ->
    Other.
        

parse_transform({block, _Line , _Name, [nil, Str]}) ->
	Str;
parse_transform(Other) ->	
	Other.
    	
    	        	
load_tag(TagName, TagArgs, Acc0, default, Ext) ->
    case parse(filename:join([erlydtl_deps:get_base_dir(), "priv", "tags", atom_to_list(TagName) ++ Ext])) of
        {ok, ParentAst} ->
		    [H|T]=ParentAst,
			{_, List, Args1} = walk_ast(H, T, [], [], undefined, Ext),
			Args2 = [{Var, Val} || {{Var, _}, Val} <- lists:zip(Args1, TagArgs)], 			
			lists:foldl(fun(X, Acc) -> 
			        [parse_transform(X, Args2) | Acc]			        
			    end, 
			    Acc0,
			    lists:reverse(List));
		{error, Msg} ->
    	    io:format("TRACE ~p:~p ~p~n",[?MODULE, ?LINE, Msg]),
    	    Acc0
    end.
 

list_fold([E]) ->
    E;      
list_fold([E1, E2]) ->
    {cons, 1, E2, E1};           
list_fold([E1, E2 | Tail]) ->
    lists:foldl(fun(X, T) -> 
        {cons, 1, X, T}
    end, {cons, 1, E2, E1}, Tail).
     
    
rel_dir(Dir, DocRoot) when Dir =:= DocRoot ->
    DocRoot;
rel_dir(Dir, DocRoot) ->
    RelFile = string:substr(Dir, length(DocRoot)+2),
    filename:join([DocRoot, RelFile]).
    