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
#include "src/gj/src/gj/gjbleserver.h"

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

  SER("\n\r");
}

#if defined(NRF)
#include "src/gj/src/gj/nrf51utils.h"
#include "softdevice_handler.h"

static void power_manage(void)
{
  uint32_t err_code = sd_app_evt_wait();
  APP_ERROR_CHECK(err_code);
}

#if defined(NRF51)
  BEGIN_BOOT_PARTITIONS()
  DEFINE_BOOT_PARTITION(0, 0x1c000, 0x10000)
  DEFINE_BOOT_PARTITION(1, 0x2d000, 0x10000)
  END_BOOT_PARTITIONS()

  DEFINE_FILE_SECTORS(config, "/config", 0x3fc00, 1);
  DEFINE_FILE_SECTORS(testfile, "/test", 0x3F800, 1);
#elif defined(NRF52)
  BEGIN_BOOT_PARTITIONS()
  DEFINE_BOOT_PARTITION(0, 0x20000, 0x20000)
  DEFINE_BOOT_PARTITION(1, 0x40000, 0x20000)
  END_BOOT_PARTITIONS()

  DEFINE_FILE_SECTORS(config, "/config", 0x7f000, 1);
  DEFINE_FILE_SECTORS(testfile, "/test", 0x7E000, 1);
#endif

GJBLEServer bleServer;

int main()
{
  RunTests();

  InitFStorage();

  uint32_t centralLinks = 0;
  uint32_t periphLinks = 1;
  InitSoftDevice(centralLinks, periphLinks);

  const char *hostName = "gjtests";
  bleServer.Init(hostName, nullptr);

  while(true)
  {
      bleServer.Update();
      GJEventManager->WaitForEvents(0);

      bool bleIdle = bleServer.IsIdle();
      bool evIdle = GJEventManager->IsIdle();
      bool const isIdle = bleIdle && evIdle;
      if (isIdle)
      {
          power_manage();
      }
  }

  return 0;
}

#endif


