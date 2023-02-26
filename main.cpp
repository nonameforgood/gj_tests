#pragma GCC optimize ("O0")

#include "src/gj/src/gj.h"

#include "src/gj/src/gj/base.h"
#include "src/gj/src/gj/esputils.h"

#include "src/gj/src/gj/datetime.h"
#include "src/gj/src/gj/commands.h"
#include "src/gj/src/gj/file.h"
#include "src/gj/src/gj/serial.h"
#include "src/gj/src/gj/config.h"
#include "src/gj/src/gj/test.h"
#include "src/gj/src/gj/eventmanager.h"

#include "src/gj/src/gj/tests/tests.h"

void RunTests()
{
  InitializeDateTime();
  InitCommands(8);
  InitSerial();
  InitESPUtils();
  InitFileSystem("");
  InitConfig();

  PrintConfig();

  uint32_t maxEvents = 4;
  GJEventManager = new EventManager(maxEvents);

  TestGJ();
}

#if defined(NRF)
#include "src/gj/src/gj/nrf51utils.h"

DEFINE_FILE_SECTORS(config, "/config", 0x2fc00, 1);
DEFINE_FILE_SECTORS(testfile, "/test", 0x30000, 1);

int main()
{
  RunTests();

  while(true)
  {
      //Make sure this program does NOT restart.
      //This is to avoid running FLASH related TESTs in an unwanted loop
      //and waste finite FLASH erase ops.
  }

  return 0;
}

#endif


