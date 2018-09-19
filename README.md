# RawInput
Background USB Scanner Support using the RAWInput API

The TftRawInputInterceptor class uses the JEDI Jvcl HidController to detect the USB scanner
and fetch it's device information.  The RAW Input API is used to read barcodes, which are then sent to the target window in a Windows message.

To compile the application define an Environment Variable in Delphi to point to the root folder of your JVCL installation.  This environment variable is used in the project search path to locate the JVCL units.
