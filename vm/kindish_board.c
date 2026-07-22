// SPDX-License-Identifier: GPL-2.0
/* QEMU compatibility-board identity expected by the Kindle userspace. */

#include <linux/init.h>
#include <linux/proc_fs.h>
#include <linux/seq_file.h>

static int kindish_identity_show(struct seq_file *file, void *unused)
{
	seq_puts(file, file->private);
	return 0;
}

static int __init kindish_board_init(void)
{
	if (!proc_create_single_data("board_id", 0444, NULL,
				     kindish_identity_show,
				     "0003M50000000000\n"))
		return -ENOMEM;
	if (!proc_create_single_data("product_name", 0444, NULL,
				     kindish_identity_show,
				     "ri7\n"))
		return -ENOMEM;
	if (!proc_create_single_data("productid", 0444, NULL,
				     kindish_identity_show, "0x0324\n"))
		return -ENOMEM;
	if (!proc_create_single_data("usid", 0444, NULL,
				     kindish_identity_show,
				     "B0D4KINDISHKT601\n"))
		return -ENOMEM;

	pr_info("Kindish QEMU compatibility board initialized\n");
	return 0;
}
device_initcall(kindish_board_init);
