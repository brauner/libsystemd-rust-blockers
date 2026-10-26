#include "assert-util.h"   /* assert_return() */
#include "hashmap.h"       /* HASHMAP_FOREACH() */
#include "log.h"           /* log_debug_errno() */
#include "macro.h"         /* TAKE_PTR(), IN_SET() */
#include "socket-util.h"   /* CMSG_FOREACH() */
#include "string-util.h"   /* streq(), strjoina() */
