module HierarchicalLogging
    using Dictionaries, Logging, LoggingCommon

    # API
    export underlying_logger
    export min_enabled_level!, insert_logger!, set_logger!, closest_registered_logger

    export ROOT_LOGGER_KEY, PropagateToChildren

    export MutableLogLevel, MutableLogLevelLogger, HierarchicalLogger

    # Re-export extra logging levels 
    export NotSet, All, Trace, Debug, Info, Notice, Warn, Error, Critical, Alert, Emergency, Fatal, AboveMax, Off

    import Base: getindex, setindex!, keys, haskey, empty!

    import Logging: min_enabled_level, handle_message, shouldlog, catch_exceptions

    import LoggingCommon: log_level 

    include("trie.jl")
    include("base.jl")
    include("hierarchical_logger.jl")
    
end