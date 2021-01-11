// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

using System;
using System.Collections.Concurrent;
using System.Linq;
using System.Text.Json;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc;

namespace Azure.Core.TestFramework.Server
{
    using static Helpers;

    [ApiController]
    [Route("[controller]/[action]")]
    public sealed class Playback : ControllerBase
    {
        // Active playback sessions. key is unique GUID
        private static readonly ConcurrentDictionary<string, RecordSession> s_sessions
            = new ConcurrentDictionary<string, RecordSession>();

        // !! TODO: Neither matching nor sanitization can be customized yet.
        private static readonly RecordMatcher s_matcher = new RecordMatcher();
        private static readonly RecordedTestSanitizer s_sanitizer = new RecordedTestSanitizer();

        // POST /playback/start: Starts a new playback session.
        //
        // Input:
        // - x-recording-file header: path to recording on local disk.
        //
        // Output:
        // - x-recording-id header:  unique ID for session
        [HttpPost]
        public async Task Start()
        {
            string file = GetHeader(Request, "x-recording-file");
            var id = Guid.NewGuid().ToString();
            using var stream = System.IO.File.OpenRead(file);
            using var doc = await JsonDocument.ParseAsync(stream).ConfigureAwait(false);
            var session = RecordSession.Deserialize(doc.RootElement);

            if (!s_sessions.TryAdd(id, session))
            {
                // This should not happen as the key is a new GUID.
                throw new InvalidOperationException("Failed to add new session.");
            }

            Response.Headers.Add("x-recording-id", id);
        }

        // POST /playback/stop: Ends a playback session.
        //
        // Input:
        // - x-recording-id: The session ID returned by prior /playback/start
        //
        // Output:
        // - None
        [HttpPost]
        public void Stop()
        {
            string id = GetHeader(Request, "x-recording-id");
            s_sessions.TryRemove(id, out _);
        }

        // Plays back a matching response for the currrent request.
        //
        // Note that the request can be anything: the method, path, body, and headers
        // are to be matched against the recording and the response will come from
        // a matching recording if one is found.
        //
        // Additional Input:
        // - x-recording-id header identifies the session to match against.
        // - x-recording-upstream uri holds the original Host that has been
        //   redirected to this test server.
        public async Task HandleRequest()
        {
            string id = GetHeader(Request, "x-recording-id");

            if (!s_sessions.TryGetValue(id, out var session))
            {
                throw new InvalidOperationException("No recording loaded with that ID.");
            }

            var entry = await CreateRecordEntry(Request).ConfigureAwait(false);
            var match = session.Lookup(entry, s_matcher, s_sanitizer);

            Response.StatusCode = match.StatusCode;

            foreach (var header in match.Response.Headers)
            {
                Response.Headers.Add(header.Key, header.Value.ToArray());
            }

            if (Request.Headers.TryGetValue("x-ms-client-id", out var clientId))
            {
                Response.Headers.Add("x-ms-client-id", clientId);
            }

            Response.Headers.Remove("Transfer-Encoding");

            if (match.Response.Body?.Length > 0)
            {
                Response.ContentLength = match.Response.Body.Length;
                await Response.Body.WriteAsync(match.Response.Body).ConfigureAwait(false);
            }
        }
    }
}
