#include <stdlib.h>

size_t
write_data(void *buffer, size_t size, size_t nmemb,
	void *userp);

void
print_usage();

int
store_link(const char *path, const char *buf);

void
print_help();

void
progress(void *clientp,
	double dltotal,
	double dlnow,
	double ultotal,
	double ulnow);

