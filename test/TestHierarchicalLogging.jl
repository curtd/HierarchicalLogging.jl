using HierarchicalLogging
using HierarchicalLogging.LoggingCommon
using Logging, TestingUtilities, Test 
import Logging: min_enabled_level, shouldlog, handle_message

module ModuleA
    module ModuleB 
        module ModuleC 
        end
    end
end
module ModuleA2
    module ModuleB1
    end
end

function trim_main_module(m)
    m_str = string(m)
    m_str_split = split(m_str, ".")
    if m_str_split[1] == "Main"
        m_str_split = m_str_split[2:end]
    end
    if length(m_str_split) ≥ 1 && m_str_split[1] == "TestHierarchicalLogger"
        m_str_split = m_str_split[2:end]
    end
    return join(m_str_split, ".")
end

struct SampleRecord 
    level::LogLevel 
    message::String
    _module::Union{Module, String} 
    group::Union{String, Nothing}
    id::Union{String, Nothing}
    file::String
    line::Int
end

Base.@kwdef struct BaseLogger <: AbstractLogger
    messages::Vector{SampleRecord} = Vector{SampleRecord}()
    current_level::MutableLogLevel = MutableLogLevel(Off)
end
Logging.min_enabled_level(logger::BaseLogger) = logger.current_level[]
Logging.shouldlog(logger::BaseLogger, level, args...) = level ≥ logger.current_level[]

function Logging.handle_message(s::BaseLogger, level, message, _module, group, id, file, line)
    r = SampleRecord(level, message, trim_main_module(_module), !isnothing(group) ? string(group) : nothing, !isnothing(id) ? string(id) : nothing, file, line)
    push!(s.messages, r)
    return nothing
end

root_logger_key = HierarchicalLogging.ROOT_LOGGER_KEY
root_logger_id = ""

A_logger_name = "ModuleA"
A_B_logger_name = "ModuleA.ModuleB"
A_B_C_logger_name = "ModuleA.ModuleB.ModuleC"
A2_logger_name = "ModuleA2"
A2_B1_logger_name = "ModuleA2.ModuleB1"

@testset "HierarchicalLogger" begin 
    @testset "Trie" begin 
        t = HierarchicalLogging.Trie{SubString{String}, Int}()
        @Test isempty(t)
        t[root_logger_key] = 1
        @Test keys(t) == [ root_logger_key ]
        t[[SubString("A"), SubString("B")]] = 2
        @Test keys(t) == [ root_logger_key, [SubString("A"), SubString("B")] ]
        @Test HierarchicalLogging.keys_with_prefix(t, root_logger_key) == [root_logger_key, [SubString("A"), SubString("B")]]
        @test HierarchicalLogging.keys_with_prefix(t, [SubString("A")]) == [ [SubString("A"), SubString("B")] ]
        t[[SubString("A"), SubString("B"), SubString("C"), SubString("D")]] = 3
        @test HierarchicalLogging.keys_with_prefix(t, root_logger_key) == [root_logger_key, [SubString("A"), SubString("B")], [SubString("A"), SubString("B"), SubString("C"), SubString("D")]]
        
        @test HierarchicalLogging.keys_with_prefix(t, [SubString("A")]) == [ [SubString("A"), SubString("B")], [SubString("A"), SubString("B"), SubString("C"), SubString("D")]]
    end
    @testset "Utilities" begin 
        root_logger = BaseLogger(; current_level=MutableLogLevel(Info))
        A_logger = BaseLogger(; current_level=MutableLogLevel(Info))
        A_B_logger = BaseLogger(; current_level=MutableLogLevel(Info))
        A_B_C_logger = BaseLogger(; current_level=MutableLogLevel(Info))
        A2_logger = BaseLogger(; current_level=MutableLogLevel(Info))
        A2_B1_logger = BaseLogger(; current_level=MutableLogLevel(Info))

        h = HierarchicalLogger(root_logger, propagate=PropagateToChildren.AllChildren)
        ref_root_logger = h.loggers[SubString{String}[]]
        @test_cases begin 
            input                    | closest_logger    | log_level | is_key
            ""                       | ref_root_logger   | Info      | true
            ModuleA                  | ref_root_logger   | Info      | false
            ModuleA.ModuleB          | ref_root_logger   | Info      | false
            ModuleA.ModuleB.ModuleC  | ref_root_logger   | Info      | false
            ModuleA2                 | ref_root_logger   | Info      | false 
            ModuleA2.ModuleB1        | ref_root_logger   | Info      | false
            "ModuleC"                | ref_root_logger   | Info      | false
            @test closest_registered_logger(h, HierarchicalLogging.to_key(h, input)) === closest_logger
            @test min_enabled_level(h, input) == log_level
            @test haskey(h, input) == is_key
        end

        insert_logger!(h, A_logger_name, A_logger)
        ref_A_logger = h.loggers[[SubString("ModuleA")]]
 
        @test_cases begin 
            input                    | output           | log_level | is_key
            ""                       | ref_root_logger  | Info      | true
            ModuleA                  | ref_A_logger     | Info      | true
            ModuleA.ModuleB          | ref_A_logger     | Info      | false
            ModuleA.ModuleB.ModuleC  | ref_A_logger     | Info      | false
            ModuleA2                 | ref_root_logger  | Info      | false 
            ModuleA2.ModuleB1        | ref_root_logger  | Info      | false 
            "ModuleC"                | ref_root_logger  | Info      | false
            @test HierarchicalLogging.closest_registered_logger(h, HierarchicalLogging.to_key(h, input)) === output
            @test min_enabled_level(h, input) == log_level
            @test haskey(h, input) == is_key
        end

        insert_logger!(h, A_B_C_logger_name, A_B_C_logger)
        ref_A_B_C_logger = h.loggers[[SubString("ModuleA"), SubString("ModuleB"), SubString("ModuleC")]]

        @test_cases begin 
            input                    | output            | log_level | is_key
            ""                       | ref_root_logger   | Info      | true
            ModuleA                  | ref_A_logger      | Info      | true
            ModuleA.ModuleB          | ref_A_logger      | Info      | false
            ModuleA.ModuleB.ModuleC  | ref_A_B_C_logger  | Info      | true 
            ModuleA2                 | ref_root_logger   | Info      | false
            ModuleA2.ModuleB1        | ref_root_logger   | Info      | false
            "ModuleC"                | ref_root_logger   | Info      | false
            @test HierarchicalLogging.closest_registered_logger(h, HierarchicalLogging.to_key(h, input)) === output
            @test min_enabled_level(h, input) == log_level
            @test haskey(h, input) == is_key
        end

        # Requested level is lower than the current level for node + its children -- ignore
        min_enabled_level!(h, ModuleA, Debug)
        @test_cases begin 
            input                    | output            | log_level | is_key
            ""                       | ref_root_logger   | Info      | true
            ModuleA                  | ref_A_logger      | Info      | true
            ModuleA.ModuleB          | ref_A_logger      | Info      | false
            ModuleA.ModuleB.ModuleC  | ref_A_B_C_logger  | Info      | true 
            ModuleA2                 | ref_root_logger   | Info      | false
            ModuleA2.ModuleB1        | ref_root_logger   | Info      | false
            "ModuleC"                | ref_root_logger   | Info      | false
            @test HierarchicalLogging.closest_registered_logger(h, HierarchicalLogging.to_key(h, input)) === output
            @test min_enabled_level(h, input) == log_level
            @test haskey(h, input) == is_key
        end

        min_enabled_level!(h, ModuleA, Off)
        @test_cases begin 
            input                    | output            | log_level | is_key
            ""                       | ref_root_logger   | Info      | true
            ModuleA                  | ref_A_logger      | Off       | true
            ModuleA.ModuleB          | ref_A_logger      | Off       | false
            ModuleA.ModuleB.ModuleC  | ref_A_B_C_logger  | Off       | true 
            ModuleA2                 | ref_root_logger   | Info      | false
            ModuleA2.ModuleB1        | ref_root_logger   | Info      | false
            "ModuleC"                | ref_root_logger   | Info      | false
            @test HierarchicalLogging.closest_registered_logger(h, HierarchicalLogging.to_key(h, input)) === output
            @test min_enabled_level(h, input) == log_level
            @test haskey(h, input) == is_key
        end

        min_enabled_level!(h, ModuleA.ModuleB, Warn; force=true)
        ref_new_A_B_logger = MutableLogLevelLogger(underlying_logger(ref_A_logger), Warn, A_B_logger_name)
        @test_cases begin 
            input                    | output            | log_level | is_key
            ""                       | ref_root_logger   | Info      | true
            ModuleA                  | ref_A_logger      | Off       | true
            ModuleA.ModuleB          | ref_new_A_B_logger| Warn      | true
            ModuleA.ModuleB.ModuleC  | ref_A_B_C_logger  | Warn      | true 
            ModuleA2                 | ref_root_logger   | Info      | false
            ModuleA2.ModuleB1        | ref_root_logger   | Info      | false
            "ModuleC"                | ref_root_logger   | Info      | false
            @test HierarchicalLogging.closest_registered_logger(h, HierarchicalLogging.to_key(h, input)) == output
            @test min_enabled_level(h, input) == log_level
            @test haskey(h, input) == is_key
        end
        

        insert_logger!(h, A2_B1_logger_name, A2_B1_logger)
        ref_A2_B1_logger = h.loggers[[SubString("ModuleA2"), SubString("ModuleB1")]]

        @test_cases begin 
            input                    | output            | log_level | is_key
            ""                       | ref_root_logger   | Info      | true
            ModuleA                  | ref_A_logger      | Off       | true
            ModuleA.ModuleB          | ref_new_A_B_logger| Warn      | true
            ModuleA.ModuleB.ModuleC  | ref_A_B_C_logger  | Warn      | true 
            ModuleA2                 | ref_root_logger   | Info      | false
            ModuleA2.ModuleB1        | ref_A2_B1_logger  | Info      | true
            "ModuleC"                | ref_root_logger   | Info      | false
            @test HierarchicalLogging.closest_registered_logger(h, HierarchicalLogging.to_key(h, input)) == output
            @test min_enabled_level(h, input) == log_level
            @test haskey(h, input) == is_key
        end

    end
    @testset "Root has no children" begin 
        root_logger = BaseLogger(; current_level=MutableLogLevel(Info))
        logger1 = BaseLogger(; current_level=MutableLogLevel(Info))
        logger1_child1 = BaseLogger(; current_level=MutableLogLevel(Info))
        logger1_child1_child1 = BaseLogger(; current_level=MutableLogLevel(Info))
        logger2 = BaseLogger(; current_level=MutableLogLevel(Info))
        logger2_child1 = BaseLogger(; current_level=MutableLogLevel(Info))
        h = HierarchicalLogger(root_logger)
        @Test haskey(h, root_logger_key)
        @Test underlying_logger(h[root_logger_key]) === root_logger
        @Test min_enabled_level(h) == Info 
        @Test h.current_logging_level[] == Info
    
        for l in [root_logger_id, A_logger_name, A_B_logger_name, A2_B1_logger_name]
            @Test h[l].base_logger === root_logger
        end

        ref_messages = Dict{String, Vector{SampleRecord}}(k => Vector{SampleRecord}() for k in [root_logger_id, A_logger_name, A_B_logger_name, A2_B1_logger_name])

        handle_message(h, Info, "Hi", Base, nothing, nothing, "a.jl", 1)
        push!(ref_messages[root_logger_id], SampleRecord(Info, "Hi", "Base", nothing, nothing, "a.jl", 1))
        @Test root_logger.messages == ref_messages[root_logger_id]

        @Test shouldlog(h, Info, root_logger_id, Main, nothing, nothing)
        @Test !shouldlog(h, Debug, root_logger_id, Main, nothing, nothing)
    
        @Test min_enabled_level(h) == Info
        @Test shouldlog(h, Info, root_logger_key)
        @Test !shouldlog(h, Debug, root_logger_key)
        
        @Test min_enabled_level!(h, Debug; force=false) == Info 
        @Test min_enabled_level(h) == Info
        @Test min_enabled_level(h, root_logger_key) == Info
        @Test min_enabled_level!(h, Debug; force=true) == Debug
        @Test min_enabled_level(h) == Debug
        @Test shouldlog(h, Info, root_logger_key)

        # Respects the underlying min_enabled_level
        @Test !shouldlog(h, Debug, root_logger_key)
        root_logger.current_level[] = All
        @Test shouldlog(h, Debug, root_logger_key)

        @Test HierarchicalLogging.all_children(h, root_logger_key) |> isempty
        @Test HierarchicalLogging.direct_children(h, root_logger_key) |> isempty
    end
    @testset "Root has depth-1 children" begin 
        root_logger = BaseLogger(; current_level=MutableLogLevel(Info))
        logger1 = BaseLogger(; current_level=MutableLogLevel(Info))
        logger1_child1 = BaseLogger(; current_level=MutableLogLevel(Info))
        logger1_child1_child1 = BaseLogger(; current_level=MutableLogLevel(Info))
        logger2 = BaseLogger(; current_level=MutableLogLevel(Info))
        logger2_child1 = BaseLogger(; current_level=MutableLogLevel(Info))

        all_loggers = Dict(root_logger_id => root_logger, A_logger_name => logger1, A_B_logger_name => logger1_child1, A2_logger_name => logger2, A2_B1_logger_name => logger2_child1)

        ref_messages = Dict{String, Vector{SampleRecord}}(k => Vector{SampleRecord}() for k in keys(all_loggers))

        h = HierarchicalLogger(root_logger)

        insert_logger!(h, A_logger_name, logger1)
        @test_throws ErrorException insert_logger!(h, A_logger_name, logger1)
        @Test h[root_logger_id].base_logger == root_logger
        @Test h[A2_logger_name].base_logger == root_logger
        @Test h[A2_B1_logger_name].base_logger == root_logger
        @Test h[A_logger_name].base_logger == logger1
        @Test h[A_B_logger_name].base_logger == logger1
        @Test min_enabled_level(h[root_logger_id]) == Info
        @Test min_enabled_level(h[A_logger_name]) == Info
        @Test min_enabled_level(h) == Info

        @Test HierarchicalLogging.all_children(h, root_logger_key) == [split(A_logger_name, h.delimiter)]
        @Test HierarchicalLogging.direct_children(h, root_logger_key) == [split(A_logger_name, h.delimiter)]
        @Test HierarchicalLogging.all_children(h, A_logger_name) |> isempty
        @Test HierarchicalLogging.direct_children(h, A_logger_name) |> isempty

        @Test shouldlog(h, Info, "Main", nothing, nothing)
        @Test shouldlog(h, Info, "ModuleA", nothing, nothing)
        @Test !shouldlog(h, Debug, "ModuleA", nothing, nothing)
        
        # min_enabled_level! only affects the current module + its children 
        @Test min_enabled_level!(h, "ModuleA", Error, force=true) == Error
        @Test shouldlog(h, Info, "Main", nothing, nothing)
        @Test !shouldlog(h, Info, "ModuleA", nothing, nothing)
        @Test shouldlog(h, Error, "ModuleA", nothing, nothing)
        @Test min_enabled_level(h) == Info
        
        push!(ref_messages[A_logger_name], SampleRecord(Info, "Hi", "ModuleA", nothing, nothing, "a.jl", 1))
        handle_message(h, Info, "Hi", "ModuleA", nothing, nothing, "a.jl", 1)
        for (k,logger) in pairs(all_loggers)
            @Test logger.messages == ref_messages[k]
        end

        push!(ref_messages[A_logger_name], SampleRecord(Info, "Hi", "ModuleA", nothing, nothing, "a.jl", 1))
        handle_message(h, Info, "Hi", ModuleA, nothing, nothing, "a.jl", 1)
        for (k,logger) in pairs(all_loggers)
            @Test logger.messages == ref_messages[k]
        end

        push!(ref_messages[root_logger_id], SampleRecord(Info, "Hi", "", nothing, nothing, "a.jl", 1))
        handle_message(h, Info, "Hi", Main, nothing, nothing, "a.jl", 1)
        for (k,logger) in pairs(all_loggers)
            @Test logger.messages == ref_messages[k]
        end

        # Old logger is discarded and no longer receives messages
        new_logger1 = BaseLogger(; current_level=MutableLogLevel(Info))
        set_logger!(h, A_logger_name, new_logger1)
        
        @test underlying_logger(h[A_logger_name]) === new_logger1
        
        handle_message(h, Info, "New", ModuleA, nothing, nothing, "a.jl", 1)

        @Test new_logger1.messages == [SampleRecord(Info, "New", "ModuleA", nothing, nothing, "a.jl", 1)]
        
        for (k,logger) in pairs(all_loggers)
            @Test logger.messages == ref_messages[k]
        end
    end
    @testset "Root has depth > 1 children" begin
        root_logger = BaseLogger(; current_level=MutableLogLevel(Info))
        A_logger = BaseLogger(; current_level=MutableLogLevel(Info))
        A_B_logger = BaseLogger(; current_level=MutableLogLevel(Info))
        A_B_C_logger = BaseLogger(; current_level=MutableLogLevel(Info))
        A2_logger = BaseLogger(; current_level=MutableLogLevel(Info))
        A2_B1_logger = BaseLogger(; current_level=MutableLogLevel(Info))

        all_loggers = Dict(root_logger_id => root_logger, A_logger_name => A_logger, A_B_logger_name => A_B_logger, A2_logger_name => A2_logger, A2_B1_logger_name => A2_B1_logger)

        ref_messages = Dict{String, Vector{SampleRecord}}(k => Vector{SampleRecord}() for k in keys(all_loggers))

        h = HierarchicalLogger(root_logger, propagate=PropagateToChildren.AllChildren)

        insert_logger!(h, A_logger_name, A_logger)

        # Logging message - logger is not added but its parent is
        handle_message(h, Error, "Hi", A_B_logger_name, nothing, nothing, "a.jl", 1)
        push!(ref_messages[A_logger_name], SampleRecord(Error, "Hi", A_B_logger_name, nothing, nothing, "a.jl", 1))

        for (k,logger) in pairs(all_loggers)
            @Test logger.messages == ref_messages[k]
        end

        @test_throws ErrorException insert_logger!(h, A_logger_name, A_logger)

        @Test min_enabled_level!(h, ModuleA, Error, force=true) == Error

        # Adding a child with an existing parent inherits its logging level 
        insert_logger!(h, A_B_logger_name, A_B_logger)

        @Test HierarchicalLogging.all_children(h, root_logger_key) == [split(name, h.delimiter) for name in (A_logger_name, A_B_logger_name)]
        @Test HierarchicalLogging.direct_children(h, root_logger_key) == [split(name, h.delimiter) for name in (A_logger_name, )]

        @Test h[root_logger_id].base_logger == root_logger
        @Test h[A2_logger_name].base_logger == root_logger
        @Test h[A2_B1_logger_name].base_logger == root_logger
        @Test h[A_logger_name].base_logger == A_logger
        @Test h[A_B_logger_name].base_logger == A_B_logger

        @Test min_enabled_level(h[root_logger_id]) == Info
        @Test min_enabled_level(h[A_logger_name]) == Error
        @Test min_enabled_level(h[A_B_logger_name]) == Error

        @test_cases begin 
            target            | ref_logger 
            "Main"            | root_logger_id
            Main              | root_logger_id
            "ModuleA"         | A_logger_name
            ModuleA           | A_logger_name
            "ModuleA.ModuleB" | A_B_logger_name
            ModuleA.ModuleB   | A_B_logger_name
            @test all( shouldlog(h, level, target, nothing, nothing) == (level ≥ min_enabled_level(h[ref_logger])) for level in [Debug, Info, Error, Warn] )
        end

        # Requested level is < minimum logging level 
        min_enabled_level!(h, A_B_logger_name, Debug, force=false)
        @Test min_enabled_level(h[root_logger_id]) == Info
        @Test min_enabled_level(h[A_logger_name]) == Error
        @Test min_enabled_level(h[A_B_logger_name]) == Error

        min_enabled_level!(h, A_B_logger_name, Warn, force=false)
        @Test min_enabled_level(h[root_logger_id]) == Info
        @Test min_enabled_level(h[A_logger_name]) == Error
        @Test min_enabled_level(h[A_B_logger_name]) == Error

        min_enabled_level!(h, A_B_logger_name, Warn, force=true)
        @Test min_enabled_level(h[root_logger_id]) == Info
        @Test min_enabled_level(h[A_logger_name]) == Error
        @Test min_enabled_level(h[A_B_logger_name]) == Warn


        min_enabled_level!(h, A_logger_name, Off, force=true)
        @Test min_enabled_level(h[root_logger_id]) == Info
        @Test min_enabled_level(h[A_logger_name]) == Off
        @Test min_enabled_level(h[A_B_logger_name]) == Off

        min_enabled_level!(h, A_logger_name, Warn, force=true)
        min_enabled_level!(h, A_B_logger_name, Emergency, force=true)

        # Message is propagated to children but the child's logging level is too high, so it is not logged
        handle_message(h, Error, "Hi", ModuleA, nothing, nothing, "a.jl", 1)
        push!(ref_messages[A_logger_name], SampleRecord(Error, "Hi", "ModuleA", nothing, nothing, "a.jl", 1))

        for (k,logger) in pairs(all_loggers)
            @Test logger.messages == ref_messages[k]
        end

        # Lowering the child logger's level results in the message being propagated
        min_enabled_level!(h, A_B_logger_name, Info, force=true)
        handle_message(h, Error, "Hi", ModuleA, nothing, nothing, "a.jl", 1)
        push!(ref_messages[A_logger_name], SampleRecord(Error, "Hi", "ModuleA", nothing, nothing, "a.jl", 1))
        push!(ref_messages[A_B_logger_name], SampleRecord(Error, "Hi", "ModuleA", nothing, nothing, "a.jl", 1))
        for (k,logger) in pairs(all_loggers)
            @Test logger.messages == ref_messages[k]
        end

    end
    @testset "Attach to modules" begin 
        root_logger = BaseLogger(; current_level=MutableLogLevel(Info))
        A_logger = BaseLogger(; current_level=MutableLogLevel(Info))
        A_B_logger = BaseLogger(; current_level=MutableLogLevel(Info))
        A_B_C_logger = BaseLogger(; current_level=MutableLogLevel(Info))
        A2_logger = BaseLogger(; current_level=MutableLogLevel(Info))
        A2_B1_logger = BaseLogger(; current_level=MutableLogLevel(Info))

        all_loggers = Dict(root_logger_id => root_logger, A_logger_name => A_logger, A_B_logger_name => A_B_logger, A_B_C_logger_name => A_B_C_logger, A2_logger_name => A2_logger, A2_B1_logger_name => A2_B1_logger)

        ref_messages = Dict{String, Vector{SampleRecord}}(k => Vector{SampleRecord}() for k in keys(all_loggers))

        h = HierarchicalLogger(root_logger, propagate=PropagateToChildren.AllChildren)
        global_logger(h)

        # All messages get routed to root logger initially 
        _file = "a.jl"
        _line=1
        _group=nothing
        _id=nothing 

        @error "Errored" _module=ModuleA2.ModuleB1 _file=_file _line=_line _group=_group _id=_id
        
        push!(ref_messages[root_logger_id], SampleRecord(Error, "Errored", A2_B1_logger_name,nothing, nothing, "a.jl", 1))

        for (k,logger) in pairs(all_loggers)
            @Test logger.messages == ref_messages[k]
        end

        insert_logger!(h, ModuleA.ModuleB.ModuleC, A_B_C_logger)
        insert_logger!(h, ModuleA2, A2_logger)

        _line=2
        @error "Errored" _module=ModuleA.ModuleB.ModuleC _file=_file _line=_line _group=_group _id=_id
        
        push!(ref_messages[A_B_C_logger_name], SampleRecord(Error, "Errored", A_B_C_logger_name,nothing, nothing, "a.jl", 2))

        for (k,logger) in pairs(all_loggers)
            @Test logger.messages == ref_messages[k]
        end

        insert_logger!(h, ModuleA, A_logger)
        min_enabled_level!(h, ModuleA, Off, force=true)

        _line=3
        @error "Errored" _module=ModuleA.ModuleB.ModuleC _file=_file _line=_line _group=_group _id=_id
        @error "Errored" _module=ModuleA.ModuleB _file=_file _line=_line _group=_group _id=_id
        @error "Errored" _module=ModuleA _file=_file _line=_line _group=_group _id=_id
        @error "Errored" _module=ModuleA2.ModuleB1 _file=_file _line=_line _group=_group _id=_id
                
        push!(ref_messages[A2_logger_name], SampleRecord(Error, "Errored", A2_B1_logger_name,nothing, nothing, "a.jl", 3))

        for (k,logger) in pairs(all_loggers)
            @Test logger.messages == ref_messages[k]
        end

        # This module isn't registered with the hierarchical logger -- will add node 
        min_enabled_level!(h, ModuleA.ModuleB, Warn, force=true)

        _line=4
        @error "Errored" _module=ModuleA.ModuleB.ModuleC _file=_file _line=_line _group=_group _id=_id
        @error "Errored" _module=ModuleA.ModuleB _file=_file _line=_line _group=_group _id=_id
        @error "Errored" _module=ModuleA _file=_file _line=_line _group=_group _id=_id
        @error "Errored" _module=ModuleA2.ModuleB1 _file=_file _line=_line _group=_group _id=_id

        push!(ref_messages[A2_logger_name], SampleRecord(Error, "Errored", A2_B1_logger_name,nothing, nothing, "a.jl", 4))
        push!(ref_messages[A_B_C_logger_name], SampleRecord(Error, "Errored", A_B_C_logger_name,nothing, nothing, "a.jl", 4))
        push!(ref_messages[A_B_C_logger_name], SampleRecord(Error, "Errored", A_B_logger_name,nothing, nothing, "a.jl", 4))
        push!(ref_messages[A_logger_name], SampleRecord(Error, "Errored", A_B_logger_name,nothing, nothing, "a.jl", 4))

        for (k,logger) in pairs(all_loggers)
            @Test logger.messages == ref_messages[k]
        end
    end
end
