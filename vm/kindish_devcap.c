// SPDX-License-Identifier: MIT
/* Correct the panel identity exposed by the generic Kindle VM profile. */

#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdlib.h>
#include <string.h>

#define REAL_DEVCAP "libkindle-cap.so.1"

static void *real_devcap(void)
{
	static void *handle;

	if (!handle)
		handle = dlopen(REAL_DEVCAP, RTLD_NOW | RTLD_LOCAL | RTLD_DEEPBIND);
	return handle;
}

static int panel_metric(const char *group, const char *property, int *value)
{
	if (!strcmp(group, "screen") && !strcmp(property, "dpi"))
		*value = 300;
	else if (!strcmp(group, "screen.physical") && !strcmp(property, "width"))
		*value = 91;
	else if (!strcmp(group, "screen.physical") && !strcmp(property, "height"))
		*value = 123;
	else
		return 0;
	return 1;
}

int devcap_initialize(void)
{
	int (*initialize)(void);
	void *handle = real_devcap();

	if (!handle)
		return -1;
	initialize = dlsym(handle, "devcap_initialize");
	return initialize ? initialize() : -1;
}

int devcap_is_available(const char *feature)
{
	int (*is_available)(const char *);
	void *handle = real_devcap();

	if (!handle)
		return 0;
	is_available = dlsym(handle, "devcap_is_available");
	return is_available ? is_available(feature) : 0;
}

int devcap_get_int(const char *group, const char *property, int *error)
{
	int (*get_int)(const char *, const char *, int *);
	int value;
	void *handle;

	if (panel_metric(group, property, &value)) {
		if (error)
			*error = 0;
		return value;
	}
	handle = real_devcap();
	if (!handle)
		return -1;
	get_int = dlsym(handle, "devcap_get_int");
	return get_int ? get_int(group, property, error) : -1;
}

char *devcap_get_string(const char *group, const char *property)
{
	char *(*get_string)(const char *, const char *);
	char metric[4];
	int value;
	void *handle;

	if (panel_metric(group, property, &value)) {
		if (value == 300)
			memcpy(metric, "300", sizeof(metric));
		else if (value == 123)
			memcpy(metric, "123", sizeof(metric));
		else
			memcpy(metric, "91", 3);
		return strdup(metric);
	}
	handle = real_devcap();
	if (!handle)
		return NULL;
	get_string = dlsym(handle, "devcap_get_string");
	return get_string ? get_string(group, property) : NULL;
}
