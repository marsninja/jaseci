"""Fixture for testing that blocking sync walkers run concurrently."""

import asyncio;
import from time { time }
import from threading { current_thread }

walker :pub slow_blocking {
    has duration: float = 1.0;

    can enter with Root entry {
        import from time { sleep }
        start = time();
        sleep(self.duration);
        report {
            "thread": current_thread().name,
            "duration": time() - start
        };
    }
}

async walker :pub slow_async {
    has duration: float = 1.0;

    async can enter with Root entry {
        start = time();
        await asyncio.sleep(self.duration);
        report {
            "thread": current_thread().name,
            "duration": time() - start
        };
    }
}
