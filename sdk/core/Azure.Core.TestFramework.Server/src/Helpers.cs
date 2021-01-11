// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

using System;
using System.IO;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Http;

namespace Azure.Core.TestFramework.Server
{
    internal static class Helpers
    {
        public static string GetHeader(HttpRequest request, string name)
        {
            if (!request.Headers.TryGetValue(name, out var value))
            {
                throw new InvalidOperationException("Missing header: " + name);
            }

            return value;
        }

        public static async Task<RecordEntry> CreateRecordEntry(HttpRequest request)
        {
            var entry = new RecordEntry();
            entry.RequestUri = GetRequestUri(request).ToString();
            entry.RequestMethod = new RequestMethod(request.Method);

            foreach (var header in request.Headers)
            {
                if (IncludeHeader(header.Key))
                {
                    entry.Request.Headers.Add(header.Key, header.Value.ToArray());
                }
            }

            entry.Request.Body = await ReadAllBytesAsync(request.Body).ConfigureAwait(false);

            return entry;
        }

        public static Uri GetRequestUri(HttpRequest request)
        {
            var uri = new RequestUriBuilder();
            uri.Reset(new Uri(GetHeader(request, "x-recording-upstream-base-uri")));
            uri.Path = request.Path;
            uri.Query = request.QueryString.ToUriComponent();

            return uri.ToUri();
        }

        private static bool IncludeHeader(string header)
        {
            return !header.Equals("Host", StringComparison.OrdinalIgnoreCase)
                && !header.StartsWith("x-recording-", StringComparison.OrdinalIgnoreCase);
        }

        private static async Task<byte[]> ReadAllBytesAsync(Stream stream)
        {
            using var memory = new MemoryStream();
            using (stream)
            {
                await stream.CopyToAsync(memory).ConfigureAwait(false);
            }

            return memory.Length == 0 ? null : memory.ToArray();
        }
    }
}
